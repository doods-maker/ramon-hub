require 'rails_helper'

RSpec.describe Ramon::FluxoRelogioJob do
  let(:account) { create(:account) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }
  let(:lead) { create(:lead, account: account) }

  it 'retoma só as esperas vencidas' do
    vencida = fluxo.execucoes.create!(account: account, alvo: lead, status: 'esperando', retomar_em: 1.minute.ago)
    fluxo.execucoes.create!(account: account, alvo: create(:lead, account: account), status: 'esperando', retomar_em: 1.hour.from_now)
    expect { described_class.perform_now }.to have_enqueued_job(Ramon::FluxoAvancarJob).with(vencida.id).exactly(:once)
  end
end
