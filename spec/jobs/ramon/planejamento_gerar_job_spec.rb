require 'rails_helper'

RSpec.describe Ramon::PlanejamentoGerarJob do
  let(:account) { create(:account) }
  let(:calculo) do
    Calculo.create!(account: account, lead: create(:lead, account: account), tipo: 'planejamento',
                    snapshot: { 'geracao' => { 'estado' => 'gerando' } })
  end

  it 'vai para a fila medium e sem retry' do
    expect(described_class.new.queue_name).to eq('medium')
    expect(described_class.get_sidekiq_options['retry']).to be(false)
  end

  it 'perform chama gerar! do cálculo e ignora cálculo apagado' do
    servico = instance_double(Ramon::PlanejamentoPrevidenciario, gerar!: nil)
    allow(Ramon::PlanejamentoPrevidenciario).to receive(:new).with(calculo).and_return(servico)

    described_class.perform_now(calculo.id)
    expect(servico).to have_received(:gerar!)

    expect { described_class.perform_now(0) }.not_to raise_error
    expect(Ramon::PlanejamentoPrevidenciario).to have_received(:new).once
  end
end
