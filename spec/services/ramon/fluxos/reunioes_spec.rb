require 'rails_helper'

RSpec.describe Ramon::Fluxos::Reunioes do
  # A conta seeda o funil no after_create (Leads::SeedDefaultConfigService).
  let(:account) { create(:account) }
  let(:closer) { create(:user, account: account, name: 'Carla Closer') }
  let(:lead) do
    create(:lead, account: account, lead_stage: account.lead_stages.order(:position).first, closer: closer, name: 'João Pereira')
  end

  describe 'regras únicas (código e fluxos)' do
    it 'reunião de pé: tarefa de reunião aberta no horário, com 60 s de folga' do
      inicio = 2.days.from_now.change(usec: 0)
      task = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reunião', due_at: inicio + 30.seconds)
      expect(described_class.reuniao_aberta?(lead, inicio)).to be(true)
      task.update!(completed_at: Time.current)
      expect(described_class.reuniao_aberta?(lead, inicio)).to be(false)
      expect(described_class.reuniao_aberta?(lead, nil)).to be(false)
    end

    it 'quem recebe o lembrete: Closer e SDR; sem nenhum dos dois, os administradores' do
      admin = create(:user, account: account, role: :administrator)
      expect(described_class.destinatarios(lead)).to eq([closer.id])
      lead.update!(closer: nil)
      expect(described_class.destinatarios(lead)).to eq([admin.id])
    end
  end

  describe 'rastro do que o código avisou' do
    after { Redis::Alfred.delete("ramon:reunioes:rastro:#{account.id}") }

    it 'grava e lê de volta dentro do intervalo, com o horário da gravação' do
      agora = Time.current.change(usec: 0)
      travel_to(agora) { described_class.rastro!(account, 'tipo' => 'lembrete', 'lead_id' => 7, 'user_ids' => [1, 2]) }

      lidos = described_class.rastros(account, agora - 1.minute, agora + 1.minute)

      expect(lidos).to eq([{ 'tipo' => 'lembrete', 'lead_id' => 7, 'user_ids' => [1, 2], 'em' => agora.to_f }])
      expect(described_class.rastros(account, agora + 1.minute, agora + 2.minutes)).to eq([])
    end

    it 'apara o que passou de 8 dias na próxima gravação' do
      agora = Time.current.change(usec: 0)
      travel_to(agora - 9.days) { described_class.rastro!(account, 'tipo' => 'velho') }
      travel_to(agora) { described_class.rastro!(account, 'tipo' => 'novo') }

      lidos = described_class.rastros(account, agora - 10.days, agora + 1.minute)

      expect(lidos.pluck('tipo')).to eq(['novo'])
    end
  end

  describe 'a chave (RAMON_FLUXO_REUNIOES=on + os 3 fluxos em modo normal)' do
    let!(:fluxos) do
      described_class::GATILHOS.to_h do |chave, gatilho|
        [chave, fluxo_publicado(account, grafo_linear({ 'tipo' => gatilho }, ['parar', {}]), sistema_chave: chave, modo: 'sombra')]
      end
    end

    it 'só assume com a env ligada e os 3 normais, ligados, publicados e com o gatilho certo' do
      expect(described_class.assumiu?(account)).to be(false)
      with_modified_env(RAMON_FLUXO_REUNIOES: 'on') do
        expect(described_class.assumiu?(account)).to be(false) # ainda em sombra
        described_class.mudar_modo!(account, 'normal')
        expect(described_class.assumiu?(account)).to be(true)
        fluxos['reuniao_cancelada'].update!(ativo: false)
        expect(described_class.assumiu?(account)).to be(false) # 1 desligado na tela devolve tudo ao código
      end
      fluxos['reuniao_cancelada'].update!(ativo: true)
      expect(described_class.assumiu?(account)).to be(false) # sem a env
    end

    it 'limite do dia num dos 3 devolve tudo ao código (o Disparo pularia o fluxo e ninguém faria)' do
      with_modified_env(RAMON_FLUXO_REUNIOES: 'on') do
        described_class.mudar_modo!(account, 'normal')
        fluxos['reuniao_cancelada'].update!(limite_dia: 5)
        expect(described_class.assumiu?(account)).to be(false)
      end
    end

    it 'virar para normal sem a env é recusado; voltar para sombra vira os 3 juntos' do
      expect { described_class.mudar_modo!(account, 'normal') }.to raise_error(ArgumentError, /RAMON_FLUXO_REUNIOES/)
      with_modified_env(RAMON_FLUXO_REUNIOES: 'on') do
        described_class.mudar_modo!(account, 'normal')
        described_class.mudar_modo!(account, 'sombra')
      end
      expect(fluxos.values.map { |f| f.reload.modo }).to all(eq('sombra'))
      expect(described_class.descrever(account)).to include('o CÓDIGO faz o agendamento')
    end
  end

  describe 'os fluxos de reunião (semeados)' do
    let(:primeira) { account.lead_stages.order(:position).first }
    let(:agendada) { account.lead_stages.find_by!(label: 'fase-reuniao-agendada') }
    let(:inicio) { Time.zone.parse('2026-10-07T22:00:00Z') }
    let!(:fluxos) { described_class.semear(account).index_by(&:sistema_chave) }

    # O relógio dos fluxos (Ramon::FluxoRelogioJob) sem o resto: anda o que venceu.
    def relogio
      FluxoExecucao.where(status: 'esperando', retomar_em: ..Time.current).find_each { |e| Ramon::Fluxos::Executor.new(e).avancar! }
    end

    def trilha(chave) = FluxoExecucao.where(fluxo: fluxos[chave]).order(:id).flat_map(&:trilha).pluck('resumo')

    def sinos = trilha('lembretes_reuniao').grep(/\Afaria: sino/)

    def agendar(alvo = lead, starts_at = inicio)
      Ramon::ReuniaoAgendamento.call(lead: alvo, starts_at: starts_at, title: 'Primeiro Atendimento')
    end

    it 'semear cria os 3 em sombra, ligados e publicados, uma vez só, com a etapa do funil da conta' do
      expect(fluxos.values).to all(have_attributes(origem: 'usuario', modo: 'sombra', ativo: true))
      expect(fluxos.transform_values(&:gatilho_tipo)).to eq(described_class::GATILHOS)
      etapa = fluxos['reuniao_marcada'].versao_publicada.grafo['nos'].find { |n| n['tipo'] == 'mover_etapa' }
      expect(etapa['config']['etapa_id']).to eq(agendada.id)
      fluxos['reuniao_marcada'].update!(nome: 'Meu agendamento')
      expect(described_class.semear(account).map(&:id)).to match_array(fluxos.values.map(&:id))
      expect(fluxos['reuniao_marcada'].reload.nome).to eq('Meu agendamento')
    end

    it 'em sombra: o código agenda como sempre e o ensaio descreve o mesmo, antes de o código mexer' do
      travel_to(inicio - 10.hours) do
        expect { agendar }.to have_enqueued_job(Ramon::MeetingReminderJob).exactly(4).times
      end
      expect(lead.lead_tasks.where(kind: 'meeting').count).to eq(1) # só a do código
      expect(trilha('reuniao_marcada')).to include(
        'faria: atividade meeting_scheduled: Primeiro Atendimento em 07/10/2026 19:00',
        'faria: tarefa "Primeiro Atendimento" para 07/10 19:00',
        "faria: mover para #{agendada.name}",
        'closer: já tem Carla Closer',
        a_string_starting_with('faria: rascunho ""Oi João! Nossa conversa está confirmada pra quarta, 07/10 às 19:00.'),
        a_string_starting_with('faria: sino para Carla Closer: "Reunião marcada com João Pereira')
      )
      expect(FluxoExecucao.where(fluxo: fluxos['lembretes_reuniao']).pluck(:alvo_type, :ensaio)).to eq([['LeadTask', true]])
    end

    it 'em sombra: cada reunião tem o seu ciclo; cancelar uma não mexe na outra (E3)' do
      travel_to(inicio - 10.hours) do
        agendar
        agendar(lead, inicio + 1.hour)
        relogio
        Ramon::ReuniaoAgendamento.cancelar(task: lead.lead_tasks.find_by!(kind: 'meeting', due_at: inicio))
      end
      [8.hours, 1.hour, 30.minutes, 5.minutes].each { |antes| travel_to(inicio + 1.hour - antes + 30.seconds) { relogio } }

      expect(FluxoExecucao.where(fluxo: fluxos['lembretes_reuniao']).order(:id).pluck(:status)).to eq(%w[cancelada concluida])
      expect(sinos.size).to eq(4)
      expect(sinos).to all(start_with('faria: sino para Carla Closer: "Reunião em '))
      expect(trilha('reuniao_cancelada')).to include(a_string_starting_with('faria: apagar tarefas #'))
    end

    it 'em sombra: remarcar recomeça só o ciclo daquela reunião, pelo horário novo' do
      travel_to(inicio - 10.hours) do
        agendar
        relogio
        Ramon::ReuniaoAgendamento.remarcar(task: lead.lead_tasks.find_by!(kind: 'meeting'), starts_at: inicio + 1.day)
        relogio
      end
      ciclos = FluxoExecucao.where(fluxo: fluxos['lembretes_reuniao']).order(:id)
      expect(ciclos.pluck(:status)).to eq(%w[cancelada esperando])
      expect(ciclos.last.retomar_em).to eq(inicio) # 24h antes da reunião nova
      expect(trilha('reuniao_marcada')).to include('faria: atividade meeting_rescheduled: Primeiro Atendimento em 07/10/2026 19:00 → ' \
                                                   'Primeiro Atendimento em 08/10/2026 19:00')
    end

    it 'em sombra: lead que muda de etapa antes da reunião continua lembrado (como o código)' do
      travel_to(inicio - 10.hours) do
        agendar
        relogio
        lead.update!(lead_stage: account.lead_stages.find_by!(label: 'fase-negociacao'))
      end
      travel_to(inicio - 8.hours + 30.seconds) { relogio }
      expect(sinos.size).to eq(1)
    end

    describe 'com os fluxos no comando (RAMON_FLUXO_REUNIOES=on + modo normal)' do
      around { |ex| with_modified_env(RAMON_FLUXO_REUNIOES: 'on') { ex.run } }

      before { described_class.mudar_modo!(account, 'normal') }

      it 'marcar: os fluxos fazem tudo que o código fazia, e o código nada' do
        admin = create(:user, account: account, role: :administrator)
        novo = create(:lead, account: account, lead_stage: primeira, name: 'Ana Souza')
        create(:team_member, team: create(:team, account: account, name: 'closer'), user: closer)
        travel_to(inicio - 10.hours) { expect { agendar(novo) }.not_to have_enqueued_job(Ramon::MeetingReminderJob) }
        tarefa = novo.lead_tasks.find_by!(kind: 'meeting')
        expect([tarefa.title, tarefa.due_at, novo.reload.lead_stage, novo.closer]).to eq(['Primeiro Atendimento', inicio, agendada, closer])
        expect(novo.lead_activities.find_by!(kind: 'meeting_scheduled').to_value).to eq('Primeiro Atendimento em 07/10/2026 19:00')
        expect(novo.lead_notes.last.body).to eq(
          "RASCUNHO (revisar antes de enviar) — confirmação de reunião:\n\"Oi Ana! Nossa conversa está confirmada pra quarta, " \
          '07/10 às 19:00. Vou te esperar, tá? Se não puder comparecer, me avise com antecedência que a gente remarca sem problema."'
        )
        expect(Notification.where(notification_type: 'ramon_fluxo_aviso').pluck(:user_id)).to contain_exactly(closer.id, admin.id)
        expect(FluxoExecucao.where(fluxo: fluxos['lembretes_reuniao'], alvo: tarefa).pluck(:ensaio)).to eq([false])
      end

      it 'remarcar e cancelar: os fluxos fazem; o código só move a tarefa' do
        travel_to(inicio - 10.hours) do
          agendar
          tarefa = lead.lead_tasks.find_by!(kind: 'meeting')
          Ramon::ReuniaoAgendamento.remarcar(task: tarefa, starts_at: inicio + 1.day)
          Ramon::ReuniaoAgendamento.cancelar(task: tarefa.reload)
          expect(LeadTask.exists?(tarefa.id)).to be(false)
        end
        expect(lead.lead_activities.find_by!(kind: 'meeting_rescheduled').from_value).to eq('Primeiro Atendimento em 07/10/2026 19:00')
        expect(lead.lead_activities.where(kind: 'meeting_cancelled').count).to eq(1)
        expect(lead.lead_notes.count).to eq(2) # confirmação da marcada e da remarcada
        expect(FluxoExecucao.where(fluxo: fluxos['lembretes_reuniao']).order(:id).pluck(:status)).to eq(%w[cancelada esperando])
      end

      it 'os lembretes saem pelo fluxo, de verdade, para o Closer' do
        travel_to(inicio - 10.hours) do
          agendar
          relogio
        end
        travel_to(inicio - 8.hours + 30.seconds) { relogio }
        rotulos = closer.notifications.where(notification_type: 'ramon_fluxo_aviso').map { |n| n.meta['label'] }
        expect(rotulos).to include(a_string_starting_with('Reunião em 8h antes'))
      end

      it 'Cal.com remarcado (apaga a tarefa e marca de novo): o ciclo da tarefa apagada para, o da nova segue' do
        travel_to(inicio - 10.hours) do
          agendar
          relogio
          lead.lead_tasks.where(kind: 'meeting').destroy_all # o que o webhook do Cal.com faz no reagendamento
          agendar(lead, inicio + 1.day)
        end
        travel_to(inicio - 8.hours + 30.seconds) { relogio }
        ciclos = FluxoExecucao.where(fluxo: fluxos['lembretes_reuniao']).order(:id)
        expect(ciclos.pluck(:status)).to eq(%w[cancelada esperando])
        expect(ciclos.first.trilha.last['resumo']).to eq('cancelado: o alvo foi apagado (lead, conversa ou reunião)')
      end

      it 'um fluxo desligado na tela devolve tudo ao código, e os outros só ensaiam (nunca em dobro)' do
        fluxos['reuniao_cancelada'].update!(ativo: false)
        travel_to(inicio - 10.hours) { expect { agendar }.to have_enqueued_job(Ramon::MeetingReminderJob).exactly(4).times }
        expect(lead.lead_tasks.where(kind: 'meeting').count).to eq(1)
        expect(FluxoExecucao.where(fluxo: fluxos['reuniao_marcada']).pluck(:ensaio)).to eq([true])
      end
    end
  end
end
