require 'rails_helper'

RSpec.describe Ramon::GoogleAgenda::Token do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:expira_em) { 1.hour.from_now }
  let(:conta) do
    GoogleAgendaConta.create!(account: account, user: user, email: 'a@b.com', access_token: 'antigo', refresh_token: 'rt',
                              expira_em: expira_em)
  end
  let(:url) { 'https://accounts.google.com/o/oauth2/token' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('GOOGLE_OAUTH_CLIENT_ID', nil).and_return('cid')
    allow(GlobalConfigService).to receive(:load).with('GOOGLE_OAUTH_CLIENT_SECRET', nil).and_return('csecret')
  end

  it 'devolve o token vigente sem chamar a rede' do
    expect(described_class.valido(conta)).to eq('antigo')
    expect(WebMock).not_to have_requested(:post, url)
  end

  context 'when faltam 4 minutos' do
    let(:expira_em) { 4.minutes.from_now }

    it 'renova e grava o novo expira_em' do
      stub_request(:post, url).to_return(status: 200, headers: json,
                                         body: { access_token: 'novo', expires_in: 3600, token_type: 'Bearer' }.to_json)
      expect(described_class.valido(conta)).to eq('novo')
      conta.reload
      expect(conta.access_token).to eq('novo')
      expect(conta.refresh_token).to eq('rt')
      expect(conta.expira_em).to be > 50.minutes.from_now
    end

    it 'invalid_grant desconecta a conta e devolve nil' do
      stub_request(:post, url).to_return(status: 400, headers: json, body: { error: 'invalid_grant' }.to_json)
      expect(described_class.valido(conta)).to be_nil
      expect(conta.reload.status).to eq('desconectada')
    end

    it 'erro 503 do Google levanta Transitorio' do
      stub_request(:post, url).to_return(status: 503, headers: json, body: { error: 'unavailable' }.to_json)
      expect { described_class.valido(conta) }.to raise_error(described_class::Transitorio)
      expect(conta.reload.status).to eq('conectada')
    end

    it 'erro de rede levanta Transitorio' do
      stub_request(:post, url).to_timeout
      expect { described_class.valido(conta) }.to raise_error(described_class::Transitorio)
      expect(conta.reload.status).to eq('conectada')
    end
  end
end
