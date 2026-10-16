require 'rails_helper'

RSpec.describe AdministratorNotifications::RamonDigestMailer do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:digest) { Ramon::DailyDigestService.new(account: account) }
  let(:class_instance) { described_class.new }

  before do
    allow(described_class).to receive(:new).and_return(class_instance)
    allow(class_instance).to receive(:smtp_config_set_or_development?).and_return(true)
  end

  describe '#daily_digest' do
    it 'manda pros administradores com subject datado e conteúdo do resumo' do
      travel_to Time.utc(2026, 7, 23, 15, 0, 0) do
        mail = described_class.with(account: account).daily_digest(digest)

        expect(mail.subject).to eq('Ramon Hub — resumo de ontem · quarta, 22 de julho')
        expect(mail.to).to contain_exactly(admin.email)
        expect(mail.body.decoded).to include('Atenção hoje')
        expect(mail.body.decoded).to include("/app/accounts/#{account.id}/ramon")
        expect(mail.body.decoded).to include('Abrir o Centro de Comando')
      end
    end

    it 'na seção da IA, mostra "+N" quando passou do limite' do
      item = { lead_id: 1, lead_name: 'Maria', conversation_id: nil, texto: 'moveu para Perdido: sem resposta', ensaio: false }
      allow(digest).to receive(:yesterday_stats).and_wrap_original do |original|
        original.call.merge(funil_auto: [item], funil_auto_restantes: 3)
      end

      body = described_class.with(account: account).daily_digest(digest).body.decoded

      expect(body).to include('O que a IA mexeu ontem')
      expect(body).to include('+3 ações')
    end

    it 'no-op sem SMTP configurado' do
      allow(class_instance).to receive(:smtp_config_set_or_development?).and_return(false)

      mail = described_class.with(account: account).daily_digest(digest)

      expect(mail.message).to be_a(ActionMailer::Base::NullMail)
    end
  end
end
