require 'rails_helper'

RSpec.describe Ramon::ZapsignStatusJob do
  it 'marca assinado quando o ZapSign confirma' do
    a = create(:portal_assinatura, doc_token: 'doc-1')
    allow(Ramon::ZapsignClient).to receive(:doc).with('doc-1').and_return('status' => 'signed')
    described_class.perform_now(a.id)
    expect(a.reload.status).to eq 'signed'
    expect(a.assinado_em).to be_present
  end

  # Decisão de 12/11/2026: o gatilho "Assinatura do Painel" dispara depois da conferência, só quando o status muda.
  it 'gatilho "Assinatura do Painel" dispara depois da conferência, só quando o status muda', :aggregate_failures do
    a = create(:portal_assinatura, doc_token: 'doc-1')
    comum = fluxo_publicado(a.portal_cliente.account, grafo_linear({ 'tipo' => 'assinatura_painel' }))
    allow(Ramon::ZapsignClient).to receive(:doc).with('doc-1').and_return('status' => 'signed')

    described_class.perform_now(a.id)
    described_class.perform_now(a.id) # aviso repetido: o status não muda

    expect(comum.execucoes.sole).to have_attributes(alvo: a, ensaio: false)
  end

  it 'ZapSign fora do ar: não dispara o gatilho' do
    a = create(:portal_assinatura, doc_token: 'doc-1')
    comum = fluxo_publicado(a.portal_cliente.account, grafo_linear({ 'tipo' => 'assinatura_painel' }))
    allow(Ramon::ZapsignClient).to receive(:doc).and_raise(Ramon::ZapsignClient::UnavailableError, 'fora')

    described_class.perform_now(a.id)

    expect(comum.execucoes).to be_empty
  end

  it 'documento cancelado pelo hub não volta a mudar com o webhook de recusa' do
    a = create(:portal_assinatura, status: 'cancelado')
    allow(Ramon::ZapsignClient).to receive(:doc)
    described_class.perform_now(a.id)
    expect(a.reload.status).to eq 'cancelado'
    expect(Ramon::ZapsignClient).not_to have_received(:doc)
  end
end
