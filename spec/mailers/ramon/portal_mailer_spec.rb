require 'rails_helper'

RSpec.describe Ramon::PortalMailer do
  let(:cliente) { create(:portal_cliente, nome: 'MARIA DA SILVA', email: 'maria@exemplo.com') }

  around { |ex| with_modified_env(SMTP_ADDRESS: 'smtp.exemplo.com', PORTAL_WHATSAPP: nil) { ex.run } }

  it 'sem a chave v2: convite e código com o texto de hoje' do
    expect(described_class.with(cliente: cliente, senha: '123456').convite.subject).to eq described_class::ASSUNTO_CONVITE
    expect(described_class.with(cliente: cliente, codigo: '654321').codigo.subject).to eq described_class::ASSUNTO_CODIGO
  end

  it 'com PORTAL_TEXTOS_V2=on: assunto e texto novos, WhatsApp da equipe no convite' do
    with_modified_env PORTAL_TEXTOS_V2: 'on' do
      convite = described_class.with(cliente: cliente, senha: '123456').convite
      expect(convite.subject).to eq described_class::ASSUNTO_CONVITE_V2
      expect(convite.body.decoded).to include('123456').and include('wa.me/5548988554077')
      codigo = described_class.with(cliente: cliente, codigo: '654321').codigo
      expect(codigo.subject).to eq described_class::ASSUNTO_CODIGO_V2
      expect(codigo.body.decoded).to include('654321').and include('A sua senha continua a mesma.')
    end
  end
end
