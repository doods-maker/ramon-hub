require 'rails_helper'

RSpec.describe 'Public Cal.com Webhooks API', type: :request do
  # A conta seeda o funil no after_create (Leads::SeedDefaultConfigService).
  let(:account) { create(:account) }
  let(:secret) { 'segredo-calcom' }
  let(:stage_novo) { account.lead_stages.order(:position).first }
  let(:booking_payload) do
    {
      triggerEvent: 'BOOKING_CREATED',
      payload: {
        title: 'Consulta previdenciária between Maria da Silva and Eduardo',
        startTime: '2026-07-15T14:00:00Z',
        attendees: [{ name: 'Maria da Silva', email: 'maria@example.com', timeZone: 'America/Sao_Paulo' }],
        responses: { phone: { value: '+55 48 99988-7766' } }
      }
    }
  end

  def post_webhook(body, signature: nil)
    raw = body.to_json
    signature ||= OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, raw)
    with_modified_env(CALCOM_WEBHOOK_SECRET: secret, RAMON_LEAD_CAPTURE_ACCOUNT_ID: account.id.to_s) do
      post '/public/api/v1/calcom_webhooks', params: raw,
                                             headers: { 'CONTENT_TYPE' => 'application/json', 'X-Cal-Signature-256' => signature }
    end
  end

  describe 'POST /public/api/v1/calcom_webhooks' do
    it 'rejeita assinatura inválida com 401 sem criar nada' do
      expect do
        post_webhook(booking_payload, signature: 'assinatura-falsa')
      end.not_to change(LeadTask, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejeita quando o secret não está configurado no servidor' do
      raw = booking_payload.to_json
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, raw)
      with_modified_env(CALCOM_WEBHOOK_SECRET: nil, RAMON_LEAD_CAPTURE_ACCOUNT_ID: account.id.to_s) do
        post '/public/api/v1/calcom_webhooks', params: raw,
                                               headers: { 'CONTENT_TYPE' => 'application/json', 'X-Cal-Signature-256' => signature }
      end
      expect(response).to have_http_status(:unauthorized)
    end

    context 'when o telefone bate num contact com lead aberto' do
      let!(:contact) { create(:contact, account: account, phone_number: '+5548999887766') }
      let!(:lead) { create(:lead, account: account, lead_stage: stage_novo, contact: contact) }

      it 'cria a tarefa de reunião com due_at no horário do booking, sem duplicar lead' do
        expect { post_webhook(booking_payload) }.not_to change(Lead, :count)

        expect(response).to have_http_status(:created)
        task = lead.lead_tasks.find_by(kind: 'meeting')
        expect(task.title).to eq 'Reunião Cal.com: Consulta previdenciária'
        expect(task.due_at).to eq Time.zone.parse('2026-07-15T14:00:00Z')
      end

      it 'registra a atividade de reunião agendada no fuso do escritório' do
        post_webhook(booking_payload)

        activity = lead.lead_activities.find_by(kind: 'meeting_scheduled')
        expect(activity.to_value).to eq 'Consulta previdenciária em 15/07/2026 11:00'
      end

      it 'manda push ntfy no celular na hora da marcação' do
        expect { post_webhook(booking_payload) }
          .to have_enqueued_job(Ramon::NtfyPushJob).with(lead.id, title: "Reuniao marcada: #{lead.name}", body: /15\/07 às 11:00/)
      end

      it 'BOOKING_CANCELLED apaga a tarefa da reunião, registra a atividade e avisa no sino' do
        create(:user, account: account, role: :administrator)
        post_webhook(booking_payload)

        cancel = booking_payload.merge(triggerEvent: 'BOOKING_CANCELLED')
        canceladas = Notification.where(notification_type: 'ramon_meeting_cancelled')
        expect { post_webhook(cancel) }.to change { lead.lead_tasks.open_tasks.where(kind: 'meeting').count }.by(-1)
                                                                                                             .and change(canceladas, :count).by(1)
        expect(response).to have_http_status(:ok)
        expect(lead.lead_activities.where(kind: 'meeting_cancelled')).to be_present
      end

      it 'anda o lead para Reunião agendada sem regredir quem já passou dela' do
        post_webhook(booking_payload)
        expect(lead.reload.lead_stage.label).to eq 'fase-reuniao-agendada'

        negociacao = account.lead_stages.find_by!(label: 'fase-negociacao')
        lead.update!(lead_stage: negociacao)
        post_webhook(booking_payload.merge(triggerEvent: 'BOOKING_RESCHEDULED'))
        expect(lead.reload.lead_stage).to eq negociacao
      end

      it 'prefere o eventTitle do payload no título da tarefa' do
        payload = booking_payload.deep_merge(payload: { eventTitle: 'Primeiro Atendimento' })
        post_webhook(payload)

        expect(lead.lead_tasks.find_by(kind: 'meeting').title).to eq 'Reunião Cal.com: Primeiro Atendimento'
      end

      it 'ignora replay do mesmo POST assinado (idempotência)' do
        # o null_store do ambiente de teste nunca "lembra" — memory store real p/ exercitar o guard
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
        post_webhook(booking_payload)
        expect(response).to have_http_status(:created)

        expect { post_webhook(booking_payload) }.not_to change(LeadTask, :count)
        expect(response).to have_http_status(:ok)
      end

      it 'BOOKING_RESCHEDULED troca a tarefa antiga pela do novo horário' do
        post_webhook(booking_payload)

        reschedule = booking_payload.deep_merge(triggerEvent: 'BOOKING_RESCHEDULED',
                                                payload: { startTime: '2026-07-20T17:00:00Z' })
        post_webhook(reschedule)

        tasks = lead.lead_tasks.open_tasks.where(kind: 'meeting')
        expect(tasks.count).to eq 1
        expect(tasks.first.due_at).to eq Time.zone.parse('2026-07-20T17:00:00Z')
      end

      it 'enfileira lembretes só nos offsets ainda futuros' do
        # 12:30 → reunião 14:00: sobram 1h, 30min e 5min antes (24h e 8h já passaram)
        travel_to Time.zone.parse('2026-07-15T12:30:00Z') do
          expect { post_webhook(booking_payload) }
            .to have_enqueued_job(Ramon::MeetingReminderJob).exactly(3).times
        end
      end

      it 'cria o rascunho de confirmação com data/hora pt-BR e pedido de aviso' do
        post_webhook(booking_payload)

        note = lead.lead_notes.find_by("body LIKE 'RASCUNHO%'")
        expect(note.body).to include('quarta, 15/07 às 11:00')
        expect(note.body).to include('me avise com antecedência')
      end

      it 'BOOKING_RESCHEDULED reenfileira os lembretes pro novo horário' do
        travel_to Time.zone.parse('2026-07-15T12:30:00Z') do
          post_webhook(booking_payload)

          reschedule = booking_payload.deep_merge(triggerEvent: 'BOOKING_RESCHEDULED',
                                                  payload: { startTime: '2026-07-20T17:00:00Z' })
          expect { post_webhook(reschedule) }
            .to have_enqueued_job(Ramon::MeetingReminderJob).with(lead.id, '2026-07-20T17:00:00Z', '24h antes')
        end
      end
    end

    it 'faz match por email quando não há telefone' do
      contact = create(:contact, account: account, email: 'maria@example.com')
      lead = create(:lead, account: account, lead_stage: stage_novo, contact: contact)
      body = booking_payload.deep_merge(payload: { responses: { phone: { value: '' } } })

      expect { post_webhook(body) }.not_to change(Lead, :count)
      expect(lead.lead_tasks.where(kind: 'meeting')).to be_present
    end

    it 'sem match cria contact + lead na primeira etapa e notifica a conta' do
      create(:user, account: account, role: :administrator)

      expect { post_webhook(booking_payload) }
        .to change(Lead, :count).by(1)
        .and change(Contact, :count).by(1)
        .and change(Notification, :count).by(2)

      lead = account.leads.find_by(source: 'calcom-agenda')
      expect(lead.lead_stage.label).to eq 'fase-reuniao-agendada'
      expect(Notification.where(notification_type: 'ramon_meeting_scheduled').last.meta['quando']).to eq 'quarta, 15/07 às 11:00'
      expect(lead.contact.phone_number).to eq '+5548999887766'
      expect(lead.lead_tasks.where(kind: 'meeting')).to be_present
    end

    it 'evento desconhecido responde 200 sem criar nada' do
      expect do
        post_webhook(booking_payload.merge(triggerEvent: 'MEETING_ENDED'))
      end.not_to change(LeadTask, :count)
      expect(response).to have_http_status(:ok)
    end
  end
end
