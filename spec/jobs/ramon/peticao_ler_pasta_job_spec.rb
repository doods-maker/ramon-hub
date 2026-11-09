require 'rails_helper'

RSpec.describe Ramon::PeticaoLerPastaJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let!(:peticao) do
    account.peticoes.create!(criado_por: user, responsavel: user, status: 'conferencia', pela_pasta: true, drive_pasta_id: 'pasta',
                             leitura: { 'estado' => 'lendo' })
  end

  it 'esgotadas as tentativas, grava estado erro' do
    allow(Ramon::Peticionamento::ImportarPasta).to receive(:call).and_raise(StandardError, 'x')
    begin
      perform_enqueued_jobs(only: described_class) { described_class.perform_later(peticao.id) }
    rescue StandardError
      nil
    end
    expect(peticao.reload.leitura['estado']).to eq('erro')
  end

  it 'tentativas esgotadas com a leitura já resolvida não regravam erro' do
    allow(Ramon::Peticionamento::ImportarPasta).to receive(:call).and_raise(StandardError, 'x')
    peticao.update!(leitura: { 'estado' => 'lida' })
    begin
      perform_enqueued_jobs(only: described_class) { described_class.perform_later(peticao.id) }
    rescue StandardError
      nil
    end
    expect(peticao.reload.leitura['estado']).to eq('lida')
  end

  it 'não lê petição protocolada nem apagada' do
    allow(Ramon::Peticionamento::ImportarPasta).to receive(:call)
    peticao.update_columns(status: 'protocolada') # rubocop:disable Rails/SkipsModelValidations
    described_class.perform_now(peticao.id)
    described_class.perform_now(0)
    expect(Ramon::Peticionamento::ImportarPasta).not_to have_received(:call)
  end

  it 'chama a importação' do
    allow(Ramon::Peticionamento::ImportarPasta).to receive(:call)
    described_class.perform_now(peticao.id)
    expect(Ramon::Peticionamento::ImportarPasta).to have_received(:call).with(peticao)
  end
end
