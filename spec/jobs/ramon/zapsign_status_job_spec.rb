require 'rails_helper'

RSpec.describe Ramon::ZapsignStatusJob do
  it 'marca assinado quando o ZapSign confirma' do
    a = create(:portal_assinatura, doc_token: 'doc-1')
    allow(Ramon::ZapsignClient).to receive(:doc).with('doc-1').and_return('status' => 'signed')
    described_class.perform_now(a.id)
    expect(a.reload.status).to eq 'signed'
    expect(a.assinado_em).to be_present
  end

  it 'documento cancelado pelo hub não volta a mudar com o webhook de recusa' do
    a = create(:portal_assinatura, status: 'cancelado')
    allow(Ramon::ZapsignClient).to receive(:doc)
    described_class.perform_now(a.id)
    expect(a.reload.status).to eq 'cancelado'
    expect(Ramon::ZapsignClient).not_to have_received(:doc)
  end
end
