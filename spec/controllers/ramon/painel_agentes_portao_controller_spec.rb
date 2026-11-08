require 'rails_helper'

RSpec.describe 'Portão do painel dos agentes', type: :request do
  let(:account) { create(:account) }
  let(:eduardo) { create(:user, account: account, role: :administrator, email: 'eduardo@example.com') }
  let(:ramon) { create(:user, account: account, role: :administrator, email: 'ramon@example.com') }
  let(:intruso) { create(:user, account: account, role: :administrator, email: 'intruso@example.com') }

  def bater(cookie)
    get '/ramon_painel_agentes/portao', headers: { 'Cookie' => "cw_d_session_info=#{CGI.escape(cookie)}" }
    response.status
  end

  around do |exemplo|
    with_modified_env(RAMON_PAINEL_AGENTES_EMAILS: ' Eduardo@example.com , ramon@example.com',
                      RAMON_AGENTES_DECISORES_EMAILS: ' EDUARDO@example.com ') { exemplo.run }
  end

  it 'abre para quem está na lista, com a sessão válida do hub' do
    expect(bater(eduardo.create_new_auth_token.to_json)).to eq(204)
  end

  it 'diz ao Caddy quem é e se escreve: só quem decide escreve' do
    bater(eduardo.create_new_auth_token.to_json)
    expect(response.headers.values_at('X-Painel-Usuario', 'X-Painel-Escreve')).to eq(%w[eduardo@example.com 1])

    bater(ramon.create_new_auth_token.to_json)
    expect(response.headers.values_at('X-Painel-Usuario', 'X-Painel-Escreve')).to eq(%w[ramon@example.com 0])
  end

  it 'sem a env de decisores, ninguém escreve' do
    with_modified_env(RAMON_AGENTES_DECISORES_EMAILS: nil) do
      expect(bater(eduardo.create_new_auth_token.to_json)).to eq(204)
      expect(response.headers['X-Painel-Escreve']).to eq('0')
    end
  end

  it 'barra administrador fora da lista, sem dizer quem é' do
    expect(bater(intruso.create_new_auth_token.to_json)).to eq(401)
    expect(response.headers.keys.grep(/x-painel/i)).to be_empty
  end

  it 'barra token falso de quem está na lista' do
    sessao = eduardo.create_new_auth_token.merge('access-token' => 'falso')
    expect(bater(sessao.to_json)).to eq(401)
  end

  it 'barra sessão encerrada' do
    sessao = eduardo.create_new_auth_token
    eduardo.update!(tokens: {})
    expect(bater(sessao.to_json)).to eq(401)
  end

  it 'barra sem cookie e com cookie que não é sessão' do
    get '/ramon_painel_agentes/portao'
    expect(response).to have_http_status(:unauthorized)
    expect(bater('nao-e-json')).to eq(401)
    expect(bater('[1]')).to eq(401)
    expect(bater('{"uid":{"a":1}}')).to eq(401)
  end

  it 'sem a env, ninguém entra' do
    with_modified_env(RAMON_PAINEL_AGENTES_EMAILS: nil) do
      expect(bater(eduardo.create_new_auth_token.to_json)).to eq(401)
    end
  end
end
