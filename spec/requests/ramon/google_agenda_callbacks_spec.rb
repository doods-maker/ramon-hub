require 'rails_helper'

RSpec.describe 'Ramon Google Agenda callback', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:outro) { create(:user, role: :agent) } # de outra conta
  let(:front) { 'https://hub.test' }
  let(:destino) { "#{front}/app/accounts/#{account.id}/ramon/agenda" }
  let(:id_token) { JWT.encode({ 'email' => 'eduardo@gmail.com' }, nil, 'none') }

  def state_de(usuario, conta_id: account.id, expires_in: 15.minutes)
    "#{usuario.to_sgid(expires_in: expires_in, for: 'ramon_google_agenda')}:#{conta_id}"
  end

  def stub_troca(refresh: 'rt-novo')
    corpo = { access_token: 'at-novo', expires_in: 3600, token_type: 'Bearer', id_token: id_token }
    corpo[:refresh_token] = refresh if refresh
    stub_request(:post, %r{accounts.google.com/o/oauth2/token}).to_return(
      status: 200, body: corpo.to_json, headers: { 'Content-Type' => 'application/json' }
    )
  end

  def chamar(state)
    with_modified_env('FRONTEND_URL' => front, 'GOOGLE_OAUTH_CLIENT_ID' => 'cid', 'GOOGLE_OAUTH_CLIENT_SECRET' => 'sec') do
      get '/ramon/google_agenda/callback', params: { code: 'abc', state: state }
    end
  end

  it 'grava a conta com tokens e e-mail do id_token' do
    stub_troca
    chamar(state_de(user))
    expect(response).to redirect_to("#{destino}?google=ok")
    conta = GoogleAgendaConta.find_by(user_id: user.id)
    expect(conta).to have_attributes(email: 'eduardo@gmail.com', status: 'conectada', access_token: 'at-novo',
                                     refresh_token: 'rt-novo', account_id: account.id)
  end

  it 'reconectar atualiza a conta desconectada e mantem o refresh antigo se o Google nao devolver outro' do
    GoogleAgendaConta.create!(user: user, account: account, status: 'desconectada', refresh_token: 'rt-velho', access_token: 'x')
    stub_troca(refresh: nil)
    chamar(state_de(user))
    expect(GoogleAgendaConta.where(user_id: user.id).count).to eq(1)
    expect(GoogleAgendaConta.find_by(user_id: user.id)).to have_attributes(status: 'conectada', refresh_token: 'rt-velho', access_token: 'at-novo')
  end

  it 'state expirado redireciona com erro e nao grava' do
    state = state_de(user, expires_in: 1.minute)
    travel_to(2.minutes.from_now) { chamar(state) }
    expect(response).to redirect_to("#{destino}?google=erro")
    expect(GoogleAgendaConta.count).to eq(0)
  end

  it 'state de usuario que nao pertence a conta redireciona com erro e nao grava' do
    chamar(state_de(outro))
    expect(response).to redirect_to("#{destino}?google=erro")
    expect(GoogleAgendaConta.count).to eq(0)
  end

  it 'state adulterado redireciona com erro' do
    chamar('lixo:123')
    expect(response).to have_http_status(:redirect)
    expect(response.location).to end_with('google=erro')
    expect(GoogleAgendaConta.count).to eq(0)
  end

  it 'falha na troca do code redireciona com erro' do
    stub_request(:post, %r{accounts.google.com/o/oauth2/token}).to_return(status: 400, body: { error: 'invalid_grant' }.to_json)
    chamar(state_de(user))
    expect(response).to redirect_to("#{destino}?google=erro")
    expect(GoogleAgendaConta.count).to eq(0)
  end
end
