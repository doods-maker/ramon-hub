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
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('reuniao_marcada', lead, hash_including('quando'))
    described_class.cancelar(task: lead.lead_tasks.find_by!(kind: 'meeting'), user: user)
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('reuniao_cancelada', lead, hash_including('quando'))
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
        { 'tipo' => 'marcada', 'lead_id' => lead.id, 'inicio' => starts_at.iso8601 },
        { 'tipo' => 'remarcada', 'lead_id' => lead.id, 'inicio' => (starts_at + 1.day).iso8601 },
        { 'tipo' => 'cancelada', 'lead_id' => lead.id, 'inicio' => (starts_at + 1.day).iso8601, 'tarefa_ids' => [task.id] }
      )
      expect(rastros.map { |r| r['user_ids'].sort }).to all(eq([user.id, admin.id].sort))
    end

    context 'com os fluxos no comando (env + os 3 em modo normal)' do
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
        travel_to(Time.zone.parse('2026-07-14T12:00:00Z')) do
          expect { described_class.remarcar(task: task, starts_at: starts_at + 1.day, user: user) }
            .not_to have_enqueued_job(Ramon::MeetingReminderJob)
        end
        expect(task.reload.due_at).to eq(starts_at + 1.day)
        expect(lead.lead_activities.where(kind: 'meeting_rescheduled')).to be_empty
      end

      it 'chave ligada: um fluxo comum em reunião marcada segue disparando 1 vez, depois do fluxo migrado' do
        comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_marcada' }, ['parar', {}]))
        agendar
        expect(comum.execucoes.map { |e| [e.ensaio, e.contexto['gatilho'].key?('assumido')] }).to eq([[false, false]])
      end
    end
  end
end
