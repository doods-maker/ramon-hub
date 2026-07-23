require 'rails_helper'

RSpec.describe Ramon::DailyDigestJob do
  let!(:account) { create(:account) }
  let(:delivery) { double('delivery', deliver_now: nil) } # rubocop:disable RSpec/VerifiedDoubles
  let(:mailer_params) { double('mailer_params', daily_digest: delivery) } # rubocop:disable RSpec/VerifiedDoubles

  before do
    allow(AdministratorNotifications::RamonDigestMailer).to receive(:with).and_return(mailer_params)
  end

  def create_overdue_task
    lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by(name: 'Novo'))
    create(:lead_task, account: account, lead: lead, due_at: 2.days.ago)
  end

  describe '#perform' do
    it 'enfileira o push com título e corpo quando há tópico e conteúdo' do
      create_overdue_task
      with_modified_env NTFY_TOPIC: 'ramon-leads' do
        expect { described_class.perform_now }
          .to have_enqueued_job(Ramon::NtfyPushJob).with(title: 'Ramon Hub · seu dia', body: '1 tarefa vencida')
      end
    end

    it 'não manda push com o dia zerado, mesmo com tópico configurado' do
      with_modified_env NTFY_TOPIC: 'ramon-leads' do
        expect { described_class.perform_now }.not_to have_enqueued_job(Ramon::NtfyPushJob)
      end
    end

    it 'não manda push sem NTFY_TOPIC' do
      create_overdue_task
      expect { described_class.perform_now }.not_to have_enqueued_job(Ramon::NtfyPushJob)
    end

    it 'manda o e-mail digest pros administradores quando há SMTP' do
      with_modified_env SMTP_ADDRESS: 'smtp.example.com' do
        described_class.perform_now

        expect(AdministratorNotifications::RamonDigestMailer).to have_received(:with).with(account: account)
        expect(mailer_params).to have_received(:daily_digest).with(kind_of(Ramon::DailyDigestService))
        expect(delivery).to have_received(:deliver_now)
      end
    end

    it 'pula o e-mail silenciosamente sem SMTP_ADDRESS' do
      with_modified_env SMTP_ADDRESS: nil do
        described_class.perform_now

        expect(AdministratorNotifications::RamonDigestMailer).not_to have_received(:with)
      end
    end

    it 'uma conta com erro não derruba as demais' do
      broken = create(:account)
      allow(Ramon::DailyDigestService).to receive(:new).and_call_original
      allow(Ramon::DailyDigestService).to receive(:new).with(account: broken).and_raise(StandardError, 'boom')

      expect { described_class.perform_now }.not_to raise_error
    end
  end
end
