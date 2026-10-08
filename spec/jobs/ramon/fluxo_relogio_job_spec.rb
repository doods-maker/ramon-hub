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

  it 'rodando parado há 15 min volta e é enfileirado' do
    orfa = fluxo.execucoes.create!(account: account, alvo: lead, status: 'rodando', updated_at: 15.minutes.ago)
    recente = fluxo.execucoes.create!(account: account, alvo: create(:lead, account: account), status: 'rodando')
    expect { described_class.perform_now }.to have_enqueued_job(Ramon::FluxoAvancarJob).with(orfa.id).exactly(:once)
    expect(orfa.reload.status).to eq('esperando')
    expect(recente.reload.status).to eq('rodando')
  end

  it 'dispara os gatilhos de relógio do dia' do
    allow(Ramon::Fluxos::Relogio).to receive(:disparar_do_dia)
    described_class.perform_now
    expect(Ramon::Fluxos::Relogio).to have_received(:disparar_do_dia)
  end

  it 'dispara o Horário da conta (B5)' do
    allow(Ramon::Fluxos::HorarioConta).to receive(:disparar)
    described_class.perform_now
    expect(Ramon::Fluxos::HorarioConta).to have_received(:disparar)
  end
end
