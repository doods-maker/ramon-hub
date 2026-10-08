require 'rails_helper'

RSpec.describe Ramon::IaGastoAlerta do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  before do
    create(:user, account: account, role: :agent)
    Redis::Alfred.delete(described_class.chave(account.id))
  end

  def chamada(custo)
    LlmChamada.create!(account: account, funcao: 'copiloto', custo_usd: custo, created_at: Time.current)
  end

  def alertas = Notification.where(notification_type: 'ramon_ia_gasto')

  it 'passou do teto: sino só dos administradores, uma vez por dia', :aggregate_failures do
    account.update!(settings: (account.settings || {}).merge(described_class::CHAVE_TETO => '1.00'))

    chamada(0.6)
    described_class.verificar(chamada(0.3))
    expect(alertas.count).to eq(0)

    described_class.verificar(chamada(0.2))
    described_class.verificar(chamada(0.5))

    expect(alertas.pluck(:user_id)).to eq([admin.id])
    expect(alertas.first.meta['label']).to eq('US$ 1,10 (teto US$ 1,00)')
    expect(alertas.first.push_message_title).to include('US$ 1,10')
  end

  it 'sem teto definido não alerta' do
    described_class.verificar(chamada(50))

    expect(alertas.count).to eq(0)
  end

  it 'a gravação do uso dispara a checagem (Ramon::LlmUso)' do
    account.update!(settings: (account.settings || {}).merge(described_class::CHAVE_TETO => '0.01'))
    allow(RubyLLM.models).to receive(:find).and_call_original
    allow(RubyLLM.models).to receive(:find).with('deepseek-chat')
                                           .and_return(instance_double(RubyLLM::Model::Info, input_price_per_million: 1.0,
                                                                                             output_price_per_million: 1.0))

    Ramon::LlmUso.registrar(account_id: account.id, funcao: 'copiloto', model: 'deepseek-chat', input_tokens: 100_000, output_tokens: 0)

    expect(alertas.count).to eq(1)
  end

  describe '.passou_do_teto?' do
    it 'so com teto definido e gasto do dia no teto ou acima', :aggregate_failures do
      expect(described_class.passou_do_teto?(account)).to be(false)
      account.update!(settings: (account.settings || {}).merge(described_class::CHAVE_TETO => '1.00'))
      chamada(0.5)
      expect(described_class.passou_do_teto?(account)).to be(false)
      chamada(0.5)
      expect(described_class.passou_do_teto?(account)).to be(true)
    end
  end
end
