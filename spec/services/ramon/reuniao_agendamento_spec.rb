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
end
