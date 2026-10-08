require 'rails_helper'

RSpec.describe Captain::CadernoNoturno do
  let(:account) { create(:account, settings: { Ramon::CadernoNoturnoJob::CHAVE => true }) }
  let(:assistant) { create(:captain_assistant, account: account) }

  before do
    Captain::IaCaso.create!(account: account, assistant: assistant, titulo: 'A1', mensagens: [{ role: 'user', content: 'oi' }])
  end

  def concluida(quando)
    Captain::IaRodada.create!(account: account, assistant: assistant, status: 'concluida', created_at: quando)
  end

  it 'sem rodada anterior enfileira a da madrugada', :aggregate_failures do
    expect { described_class.new(account).perform }.to have_enqueued_job(Captain::IaRodadaJob)
    expect(Captain::IaRodada.last).to have_attributes(status: 'fila', total: 1, disparado_por_id: nil)
  end

  it 'nada mudou desde a ultima rodada: nao enfileira' do
    assistant.update_column(:updated_at, 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
    Captain::IaCaso.update_all(updated_at: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
    concluida(1.day.ago)

    expect { described_class.new(account).perform }.not_to have_enqueued_job(Captain::IaRodadaJob)
  end

  it 'chave desligada, teto estourado ou rodada em andamento: nao enfileira', :aggregate_failures do
    account.update!(settings: { Ramon::CadernoNoturnoJob::CHAVE => false })
    expect(described_class.new(account).perform).to eq([])

    account.update!(settings: { Ramon::CadernoNoturnoJob::CHAVE => true })
    allow(Ramon::IaGastoAlerta).to receive(:passou_do_teto?).and_return(true)
    expect(described_class.new(account).perform).to eq([])

    allow(Ramon::IaGastoAlerta).to receive(:passou_do_teto?).and_return(false)
    Captain::IaRodada.create!(account: account, assistant: assistant, status: 'rodando')
    expect(described_class.new(account).perform).to eq([])
  end

  it 'gasto do dia + custo estimado da rodada passaria do teto: nao enfileira (F5)', :aggregate_failures do
    allow(Ramon::IaGastoAlerta).to receive_messages(passou_do_teto?: false, teto: 1.0, gasto_hoje: 0.98)
    expect(described_class.new(account).perform).to eq([])

    allow(Ramon::IaGastoAlerta).to receive(:gasto_hoje).and_return(0.5)
    expect { described_class.new(account).perform }.to have_enqueued_job(Captain::IaRodadaJob)
  end
end
