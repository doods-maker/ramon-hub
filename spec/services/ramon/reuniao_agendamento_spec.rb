require 'rails_helper'

RSpec.describe Ramon::ReuniaoAgendamento do
  # A conta seeda o funil no after_create (Leads::SeedDefaultConfigService).
  let(:account) { create(:account) }
  let(:novo) { account.lead_stages.order(:position).first }
  let(:agendada) { account.lead_stages.find_by!(label: 'fase-reuniao-agendada') }
  let(:lead) { create(:lead, account: account, lead_stage: novo, name: 'João Pereira') }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:starts_at) { Time.zone.parse('2026-07-15T14:00:00Z') }

  def agendar(**)
    described_class.call(lead: lead, starts_at: starts_at, title: 'Primeiro Atendimento', user: user, **)
  end

  it 'grava o formato escolhido (padrão vídeo)', :aggregate_failures do
    agendar(formato: 'whatsapp')
    expect(lead.lead_tasks.find_by!(kind: 'meeting').formato).to eq 'whatsapp'
  end

  describe '.livre?' do
    it 'sem Closer no time não há agenda para conferir: livre' do
      expect(described_class.livre?(lead, starts_at)).to be(true)
    end

    it 'confere a agenda do Closer do lead; remarcando, ignora a própria reunião', :aggregate_failures do
      closer = create(:user, account: account)
      lead.update!(closer: closer)
      disponibilidade = instance_double(Ramon::Agenda::Disponibilidade, colide?: true)
      allow(Ramon::Agenda::Disponibilidade).to receive(:new).with(user: closer, account: account).and_return(disponibilidade)

      expect(described_class.livre?(lead, starts_at)).to be(false)
      expect(disponibilidade).to have_received(:colide?).with(starts_at, ignorar_task_id: nil)

      task = create(:lead_task, account: account, lead: lead, kind: 'meeting')
      described_class.livre?(lead, starts_at, task: task)
      expect(disponibilidade).to have_received(:colide?).with(starts_at, ignorar_task_id: task.id)
    end
  end

  it 'cria a tarefa de reunião, a atividade e anda o lead pra Reunião agendada', :aggregate_failures do
    agendar

    task = lead.lead_tasks.find_by!(kind: 'meeting')
    expect(task.title).to eq 'Primeiro Atendimento'
    expect(task.due_at).to eq starts_at
    expect(task.user).to eq user
    expect(lead.lead_activities.find_by!(kind: 'meeting_scheduled').to_value).to eq 'Primeiro Atendimento em 15/07/2026 11:00'
    expect(lead.reload.lead_stage).to eq agendada
  end

  it 'marcar e cancelar disparam os fluxos de reunião' do
    allow(Ramon::Fluxos::Disparo).to receive(:externo)
    agendar
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('reuniao_marcada', lead, { 'quando' => anything })
    described_class.cancelar(task: lead.lead_tasks.find_by!(kind: 'meeting'), user: user)
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('reuniao_cancelada', lead, { 'quando' => anything })
  end

  it 'usa o task_title quando informado (prefixo do Cal.com)' do
    agendar(task_title: 'Reunião Cal.com: Primeiro Atendimento')
    expect(lead.lead_tasks.find_by!(kind: 'meeting').title).to eq 'Reunião Cal.com: Primeiro Atendimento'
  end

  it 'nunca regride a etapa de quem já passou de Reunião agendada' do
    negociacao = account.lead_stages.find_by!(label: 'fase-negociacao')
    lead.update!(lead_stage: negociacao)

    agendar
    expect(lead.reload.lead_stage).to eq negociacao
  end

  it 'atribui o Closer do time closer quando o lead está sem Closer' do
    closer = create(:user, account: account, role: :agent)
    create(:team_member, team: create(:team, account: account, name: 'closer'), user: closer)

    agendar
    expect(lead.reload.closer).to eq closer
  end

  it 'enfileira só os lembretes internos ainda futuros' do
    travel_to Time.zone.parse('2026-07-15T12:30:00Z') do
      expect { agendar }.to have_enqueued_job(Ramon::MeetingReminderJob).exactly(3).times
    end
  end

  it 'deixa a confirmação como nota RASCUNHO e não manda nada ao cliente', :aggregate_failures do
    expect { agendar }.not_to change(Message, :count)

    note = lead.lead_notes.find_by!("body LIKE 'RASCUNHO%'")
    expect(note.body).to include('Oi João!')
    expect(note.body).to include('quarta, 15/07 às 11:00')
  end

  describe 'confirmação (texto aprovado 16/10)' do
    let(:closer) { create(:user, account: account) }
    let(:meet) { 'https://meet.google.com/abc-defg' }
    let(:agenda) { 'Pra salvar na sua agenda: https://calendar.google.com/calendar/render?action=TEMPLATE' }

    before { lead.update!(closer: closer) }

    def nota = lead.lead_notes.find_by!("body LIKE 'RASCUNHO%'").body

    it 'WhatsApp: a ligação no lugar do Meet, com o link da agenda', :aggregate_failures do
      agendar(formato: 'whatsapp')
      expect(nota).to include("Oi João! Nossa conversa está confirmada pra quarta, 15/07 às 11:00. Eu te ligo no WhatsApp nesse horário. #{agenda}")
      expect(nota).to end_with('Se não puder comparecer, me avise com antecedência que a gente remarca sem problema."')
    end

    it 'vídeo sem Google (sem Meet): omite a linha do formato' do
      agendar
      expect(nota).to include("às 11:00. #{agenda}")
    end

    it 'com conta Google conectada o rascunho espera o job (não nasce na marcação)', :aggregate_failures do
      GoogleAgendaConta.create!(user: closer, account: account, refresh_token: 'rt', access_token: 'at')
      expect { agendar }.to have_enqueued_job(Ramon::GoogleAgendaPushJob).with('criar', { 'task_id' => kind_of(Integer), 'rascunho' => true })
      expect(lead.lead_notes.where("body LIKE 'RASCUNHO%'")).to be_empty
    end

    it 'com os fluxos no comando e Google conectado, o rascunho também espera o job', :aggregate_failures do
      GoogleAgendaConta.create!(user: closer, account: account, refresh_token: 'rt', access_token: 'at')
      allow(Ramon::Fluxos::Reunioes).to receive(:assumiu?).and_return(true)
      expect(create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'X', due_at: starts_at).rascunho_no_job?).to be(true)
    end

    it 'confirmar com Meet inclui o link do vídeo' do
      agendar
      task = lead.lead_tasks.find_by!(kind: 'meeting')
      task.update_columns(meet_url: meet) # rubocop:disable Rails/SkipsModelValidations
      described_class.confirmar(task)
      expect(lead.lead_notes.order(:id).last.body).to include("É por vídeo, neste link: #{meet}. #{agenda}")
    end

    describe 'envio automático pela IA' do
      let(:conversa) { create(:conversation, account: account) }

      before do
        lead.update!(conversation: conversa)
        conversa.update!(custom_attributes: { 'copiloto_modo' => 'piloto_total' })
      end

      it 'chave on + piloto + marcada pela IA: manda na conversa, sem rascunho nem prefixo', :aggregate_failures do
        with_modified_env(RAMON_AGENDA_CONFIRMACAO: 'on') { agendar(automatico: true) }
        msg = conversa.messages.outgoing.last
        expect(msg.content).to start_with('Oi João! Nossa conversa está confirmada pra quarta')
        expect(msg.content).not_to include('RASCUNHO')
        expect(lead.lead_notes.where("body LIKE 'RASCUNHO%'")).to be_empty
      end

      it 'chave off (padrão): rascunho, nada enviado', :aggregate_failures do
        expect { agendar(automatico: true) }.not_to(change { conversa.messages.count })
        expect(nota).to include('Oi João!')
      end

      it 'chave on mas marcada por pessoa: rascunho' do
        with_modified_env(RAMON_AGENDA_CONFIRMACAO: 'on') { expect { agendar }.not_to(change { conversa.messages.count }) }
      end

      it 'chave on mas modo rascunho: rascunho', :aggregate_failures do
        conversa.update!(custom_attributes: { 'copiloto_modo' => 'rascunho' })
        with_modified_env(RAMON_AGENDA_CONFIRMACAO: 'on') { expect { agendar(automatico: true) }.not_to(change { conversa.messages.count }) }
        expect(nota).to include('Oi João!')
      end
    end
  end

  it 'avisa no sino da conta com o horário humano' do
    create(:user, account: account, role: :administrator)

    agendar
    expect(Notification.where(notification_type: 'ramon_meeting_scheduled').last.meta['quando']).to eq 'quarta, 15/07 às 11:00'
  end

  describe '.remarcar' do
    let(:novo_horario) { Time.zone.parse('2026-07-17T17:30:00Z') }

    def remarcar(task)
      described_class.remarcar(task: task, starts_at: novo_horario, user: user)
    end

    it 'move a tarefa, registra de→para, novo rascunho e lembretes do horário novo', :aggregate_failures do
      travel_to Time.zone.parse('2026-07-14T12:00:00Z') do
        agendar(task_title: 'Reunião Cal.com: Primeiro Atendimento')
        task = lead.lead_tasks.find_by!(kind: 'meeting')

        expect { remarcar(task) }.to have_enqueued_job(Ramon::MeetingReminderJob).exactly(5).times
        expect(task.reload.due_at).to eq novo_horario
        activity = lead.lead_activities.find_by!(kind: 'meeting_rescheduled')
        expect(activity.from_value).to eq 'Primeiro Atendimento em 15/07/2026 11:00'
        expect(activity.to_value).to eq 'Primeiro Atendimento em 17/07/2026 14:30'
        expect(lead.lead_notes.where("body LIKE 'RASCUNHO%'").count).to eq 2
        expect(lead.lead_notes.order(:id).last.body).to include('sexta, 17/07 às 14:30')
      end
    end

    it 'não manda nada ao cliente e avisa no sino com o horário novo', :aggregate_failures do
      create(:user, account: account, role: :administrator)
      agendar
      task = lead.lead_tasks.find_by!(kind: 'meeting')

      expect { remarcar(task) }.not_to change(Message, :count)
      expect(Notification.where(notification_type: 'ramon_meeting_scheduled').last.meta['quando']).to eq 'sexta, 17/07 às 14:30'
    end
  end

  describe 'sem_google (mudança que veio do Google não volta para lá)' do
    let(:task) do
      agendar
      lead.lead_tasks.find_by!(kind: 'meeting')
    end

    it 'remarcar com sem_google: true não enfileira o push' do
      task
      expect { described_class.remarcar(task: task, starts_at: starts_at + 1.day, user: user, sem_google: true) }
        .not_to have_enqueued_job(Ramon::GoogleAgendaPushJob)
    end

    it 'remarcar sem o kwarg enfileira o push' do
      task
      expect { described_class.remarcar(task: task, starts_at: starts_at + 1.day, user: user) }
        .to have_enqueued_job(Ramon::GoogleAgendaPushJob).with('atualizar', anything)
    end

    it 'cancelar com sem_google: true não enfileira o push' do
      task.update_columns(google_event_id: 'ev1') # rubocop:disable Rails/SkipsModelValidations
      expect { described_class.cancelar(task: task, user: user, sem_google: true) }.not_to have_enqueued_job(Ramon::GoogleAgendaPushJob)
    end

    it 'cancelar sem o kwarg enfileira o push' do
      task.update_columns(google_event_id: 'ev1') # rubocop:disable Rails/SkipsModelValidations
      expect { described_class.cancelar(task: task, user: user) }.to have_enqueued_job(Ramon::GoogleAgendaPushJob).with('cancelar', anything)
    end
  end

  describe '.cancelar' do
    it 'tira a tarefa, registra o cancelamento e avisa no sino', :aggregate_failures do
      create(:user, account: account, role: :administrator)
      agendar
      task = lead.lead_tasks.find_by!(kind: 'meeting')

      described_class.cancelar(task: task, user: user)

      expect(LeadTask.exists?(task.id)).to be(false)
      activity = lead.lead_activities.find_by!(kind: 'meeting_cancelled')
      expect(activity.to_value).to eq 'Primeiro Atendimento em 15/07/2026 11:00'
      expect(activity.user).to eq user
      expect(Notification.where(notification_type: 'ramon_meeting_cancelled')).to exist
    end

    it 'o lembrete já enfileirado vira órfão e não apita' do
      allow(Ramon::NtfyPushJob).to receive(:perform_now)
      agendar
      described_class.cancelar(task: lead.lead_tasks.find_by!(kind: 'meeting'))

      with_modified_env(NTFY_TOPIC: 'ramon') { Ramon::MeetingReminderJob.perform_now(lead.id, starts_at.iso8601, '1h antes') }
      expect(Ramon::NtfyPushJob).not_to have_received(:perform_now)
    end
  end

  describe 'B4.1: o evento decide uma vez quem faz' do
    it 'código no comando: o ensaio dos fluxos vem antes e leva os textos prontos' do
      tarefas_no_ensaio = nil
      allow(Ramon::Fluxos::Disparo).to receive(:externo) { |gatilho, *| tarefas_no_ensaio ||= lead.lead_tasks.count if gatilho == 'reuniao_marcada' }
      agendar
      expect(tarefas_no_ensaio).to eq(0)
      expect(Ramon::Fluxos::Disparo).to have_received(:externo).with(
        'reuniao_marcada', lead,
        hash_including('evento' => 'marcada', 'assumido' => false, 'inicio' => starts_at.iso8601, 'quem_marcou_id' => user.id,
                       'resumo' => 'Primeiro Atendimento em 15/07/2026 11:00', 'primeiro_nome' => 'João',
                       'titulo_tarefa' => 'Primeiro Atendimento')
      )
      expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('reuniao_na_agenda', lead.lead_tasks.last, hash_including('assumido' => false))
    end

    it 'remarcar leva o resumo de antes; cancelar leva as tarefas' do
      allow(Ramon::Fluxos::Disparo).to receive(:externo)
      agendar
      task = lead.lead_tasks.find_by!(kind: 'meeting')
      described_class.remarcar(task: task, starts_at: starts_at + 1.day, user: user)
      described_class.cancelar(task: task.reload, user: user)
      expect(Ramon::Fluxos::Disparo).to have_received(:externo)
        .with('reuniao_marcada', lead, hash_including('evento' => 'remarcada', 'resumo_antes' => 'Primeiro Atendimento em 15/07/2026 11:00'))
      expect(Ramon::Fluxos::Disparo).to have_received(:externo)
        .with('reuniao_cancelada', lead, hash_including('evento' => 'cancelada', 'tarefa_ids' => [task.id]))
    end

    it 'chave desligada: um fluxo comum em reunião marcada dispara 1 vez, depois dos efeitos (vê a etapa já movida)' do
      comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_marcada' }, ['parar', {}]))
      agendar
      expect(comum.execucoes.map { |e| [e.ensaio, e.contexto['etapa_inicial_id'], e.contexto['gatilho'].key?('assumido')] })
        .to eq([[false, agendada.id, false]])
    end

    it 'o sino do código deixa rastro (Redis) para a comparação: marcada, remarcada e cancelada' do
      admin = create(:user, account: account, role: :administrator)
      Redis::Alfred.delete(Ramon::Fluxos::Reunioes.chave_rastro(account))
      agendar
      task = lead.lead_tasks.find_by!(kind: 'meeting')
      described_class.remarcar(task: task, starts_at: starts_at + 1.day, user: user)
      described_class.cancelar(task: task.reload, user: user)

      rastros = Ramon::Fluxos::Reunioes.rastros(account, 1.minute.ago, 1.minute.from_now)
      expect(rastros.map { |r| r.except('em', 'user_ids') }).to contain_exactly(
        { 'tipo' => 'marcada', 'lead_id' => lead.id, 'inicio' => starts_at.iso8601, 'tarefa' => 'Primeiro Atendimento' },
        { 'tipo' => 'remarcada', 'lead_id' => lead.id, 'inicio' => (starts_at + 1.day).iso8601 },
        { 'tipo' => 'cancelada', 'lead_id' => lead.id, 'inicio' => (starts_at + 1.day).iso8601, 'tarefa_ids' => [task.id] }
      )
      expect(rastros.map { |r| r['user_ids'].sort }).to all(eq([user.id, admin.id].sort))
    end

    describe 'com os fluxos no comando (env + os 3 em modo normal)' do
      around { |ex| with_modified_env(RAMON_FLUXO_REUNIOES: 'on') { ex.run } }

      before do
        Ramon::Fluxos::Reunioes::GATILHOS.each do |chave, gatilho|
          fluxo_publicado(account, grafo_linear({ 'tipo' => gatilho }, ['parar', {}]), sistema_chave: chave, modo: 'normal')
        end
      end

      it 'marcar e cancelar: o código só dispara (quem faz é o fluxo — aqui, de teste, só "parar")' do
        travel_to(Time.zone.parse('2026-07-14T12:00:00Z')) do
          expect { agendar }.not_to have_enqueued_job(Ramon::MeetingReminderJob)
        end
        expect([lead.lead_tasks.count, lead.lead_activities.where(kind: 'meeting_scheduled').count, lead.lead_notes.count]).to eq([0, 0, 0])
        task = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Primeiro Atendimento', due_at: starts_at)
        described_class.cancelar(task: task, user: user)
        expect(LeadTask.exists?(task.id)).to be(true)
      end

      it 'remarcar: o código só move a tarefa' do
        task = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Primeiro Atendimento', due_at: starts_at)
        allow(Ramon::Fluxos::Reunioes).to receive(:assumiu?).and_call_original
        travel_to(Time.zone.parse('2026-07-14T12:00:00Z')) do
          expect { described_class.remarcar(task: task, starts_at: starts_at + 1.day, user: user) }
            .not_to have_enqueued_job(Ramon::MeetingReminderJob)
        end
        expect(task.reload.due_at).to eq(starts_at + 1.day)
        expect(lead.lead_activities.where(kind: 'meeting_rescheduled')).to be_empty
        expect(Ramon::Fluxos::Reunioes).to have_received(:assumiu?).once # o evento decide uma vez só
      end

      it 'marcar com WhatsApp: o passo "Criar tarefa" do fluxo cria a reunião com formato whatsapp (o gatilho leva o formato)' do
        marcada = Fluxo.find_by!(account: account, sistema_chave: Ramon::Fluxos::Reunioes::GATILHOS.key('reuniao_marcada'))
        marcada.update!(rascunho: grafo_linear({ 'tipo' => 'reuniao_marcada' },
                                               ['criar_tarefa', { 'titulo' => 'Reunião', 'tipo' => 'meeting', 'prazo' => 'reuniao' }]))
        marcada.publicar!(nil)
        agendar(formato: 'whatsapp')
        expect(lead.lead_tasks.where(kind: 'meeting').pluck(:formato)).to eq(['whatsapp'])
      end

      it 'chave ligada: um fluxo comum em reunião marcada segue disparando 1 vez, depois do fluxo migrado' do
        comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_marcada' }, ['parar', {}]))
        agendar
        expect(comum.execucoes.map { |e| [e.ensaio, e.contexto['gatilho'].key?('assumido')] }).to eq([[false, false]])
      end
    end
  end
end
