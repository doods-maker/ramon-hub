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

  it 'órfã volta contando a tentativa; na 4ª queda do mesmo passo falha em vez de repetir para sempre' do
    orfa = fluxo.execucoes.create!(account: account, alvo: lead, status: 'rodando', updated_at: 15.minutes.ago)
    3.times do |i|
      described_class.perform_now
      expect(orfa.reload).to have_attributes(status: 'esperando', tentativas: i + 1)
      orfa.update_columns(status: 'rodando', retomar_em: nil, updated_at: 15.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
    end
    expect { described_class.perform_now }.to have_enqueued_job(Ramon::NtfyPushJob)
    expect(orfa.reload).to have_attributes(status: 'falhou', erro: include('as tentativas acabaram'))
    expect(orfa.trilha.last).to include('erro' => true, 'resumo' => include('as tentativas acabaram'))
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

  it 'erro no relógio do dia não impede o Horário da conta' do
    allow(Ramon::Fluxos::Relogio).to receive(:disparar_do_dia).and_raise(StandardError, 'boom')
    allow(Ramon::Fluxos::HorarioConta).to receive(:disparar)
    expect { described_class.perform_now }.not_to raise_error
    expect(Ramon::Fluxos::HorarioConta).to have_received(:disparar)
  end
end
