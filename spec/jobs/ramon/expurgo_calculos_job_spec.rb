require 'rails_helper'

RSpec.describe Ramon::ExpurgoCalculosJob do
  let(:account) { create(:account) }
  let(:rascunho) { create(:lead, account: account, source: Lead::FONTE_CALCULO, contact: nil) }
  let(:cliente) { create(:lead, account: account, contact: create(:contact, account: account)) }

  def calculo(lead, dias)
    Calculo.create!(account: account, lead: lead, tipo: 'rmi', created_at: dias.days.ago)
  end

  it 'apaga só os cálculos do rascunho com mais de 30 dias' do
    velho = calculo(rascunho, 31)
    recente = calculo(rascunho, 29)
    do_cliente = calculo(cliente, 400)

    described_class.perform_now

    expect(Calculo.where(id: velho.id)).not_to exist
    expect(Calculo.where(id: [recente.id, do_cliente.id]).count).to eq(2)
    expect(Lead.where(id: rascunho.id)).to exist
  end
end
