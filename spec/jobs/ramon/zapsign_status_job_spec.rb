require 'rails_helper'

RSpec.describe Ramon::ZapsignStatusJob do
  it 'marca assinado quando o ZapSign confirma' do
    a = create(:portal_assinatura, doc_token: 'doc-1')
    allow(Ramon::ZapsignClient).to receive(:doc).with('doc-1').and_return('status' => 'signed')
    described_class.perform_now(a.id)
    expect(a.reload.status).to eq 'signed'
    expect(a.assinado_em).to be_present
  end

  it '"pending" do ZapSign mantém o pendente do hub (segue na lista de pendentes) e não dispara o gatilho', :aggregate_failures do
    a = create(:portal_assinatura, doc_token: 'doc-1')
    comum = fluxo_publicado(a.portal_cliente.account, grafo_linear({ 'tipo' => 'assinatura_painel' }))
    allow(Ramon::ZapsignClient).to receive(:doc).with('doc-1').and_return('status' => 'pending')

    described_class.perform_now(a.id)

    expect(a.reload.status).to eq 'pendente'
    expect(PortalAssinatura.pendentes).to include(a)
    expect(comum.execucoes).to be_empty
  end

  it 'recusado no ZapSign grava o status e não dispara o gatilho (só assinatura confirmada)', :aggregate_failures do
    a = create(:portal_assinatura, doc_token: 'doc-1')
    comum = fluxo_publicado(a.portal_cliente.account, grafo_linear({ 'tipo' => 'assinatura_painel' }))
    allow(Ramon::ZapsignClient).to receive(:doc).with('doc-1').and_return('status' => 'refused')

    described_class.perform_now(a.id)

    expect(a.reload.status).to eq 'refused'
    expect(comum.execucoes).to be_empty
  end

  # Decisão de 12/11/2026: o gatilho "Assinatura do Painel" dispara depois da conferência, só com a assinatura confirmada.
  it 'gatilho "Assinatura do Painel" dispara depois da conferência, uma vez por assinatura confirmada', :aggregate_failures do
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
