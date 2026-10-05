require 'rails_helper'

RSpec.describe Ramon::PortalConvite do
  let(:cliente) do
    create(:portal_cliente, nome: 'MARIA DE LOURDES', cpf: '12345678901', email: nil, telefone: '48999887766', convidado_em: nil)
  end

  it 'gera a senha, carimba o 1º convite e não reescreve a data numa senha nova' do
    resposta = described_class.new(cliente).perform
    expect(cliente.authenticate_senha(resposta[:senha_provisoria])).to be_truthy
    primeiro = cliente.reload.convidado_em
    expect(primeiro).to be_present

    travel 1.day do
      described_class.new(cliente).perform
    end
    expect(cliente.reload.convidado_em).to eq primeiro
  end

  it 'sem telefone: mensagem pronta sim, link de WhatsApp não' do
    cliente.update!(telefone: nil)
    resposta = described_class.new(cliente).perform
    expect(resposta[:mensagem]).to include(resposta[:senha_provisoria])
    expect(resposta[:whatsapp_url]).to be_nil
  end

  it 'mensagem com endereço, CPF formatado e senha; wa.me com DDI 55' do
    with_modified_env PORTAL_URL: 'https://cliente.exemplo.com' do
      resposta = described_class.new(cliente).perform
      expect(resposta[:mensagem]).to include('Olá, Maria!', 'https://cliente.exemplo.com', '123.456.789-01', resposta[:senha_provisoria])
      expect(resposta[:whatsapp_url]).to start_with('https://wa.me/5548999887766?text=Ol%C3%A1')
    end
  end
end
