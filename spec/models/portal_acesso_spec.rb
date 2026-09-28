require 'rails_helper'

RSpec.describe PortalAcesso do
  it 'expurga só os registros com mais de 6 meses (Marco Civil art. 15)' do
    cliente = create(:portal_cliente)
    velho = described_class.create!(portal_cliente: cliente, ip: '1.1.1.1', created_at: 7.months.ago)
    recente = described_class.create!(portal_cliente: cliente, ip: '1.1.1.1', created_at: 5.months.ago)
    described_class.expurgar!
    expect(described_class.pluck(:id)).to eq([recente.id])
    expect(described_class.exists?(velho.id)).to be false
  end
end
