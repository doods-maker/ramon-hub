require 'rails_helper'

RSpec.describe Ramon::ZapsignStatusJob do
  it 'marca assinado quando o ZapSign confirma' do
    a = create(:portal_assinatura, doc_token: 'doc-1')
    allow(Ramon::ZapsignClient).to receive(:doc).with('doc-1').and_return('status' => 'signed')
    described_class.perform_now(a.id)
    expect(a.reload.status).to eq 'signed'
    expect(a.assinado_em).to be_present
  end
end
