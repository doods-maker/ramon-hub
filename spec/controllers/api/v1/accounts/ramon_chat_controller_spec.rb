require 'rails_helper'

RSpec.describe 'Ramon Chat API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:brenda) { create(:user, account: account, role: :agent) }
  let(:eduardo) { create(:user, account: account, role: :agent) }
  let(:gabriela) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_chat" }
  let(:direto) { ChatCanal.direto!(account, brenda, eduardo) }

  def enviar(canal, user, conteudo = 'oi')
    post "#{url}/#{canal.id}/enviar", params: { conteudo: conteudo }, headers: user.create_new_auth_token, as: :json
  end

  def ler_canal(canal, user)
    get "#{url}/#{canal.id}", headers: user.create_new_auth_token, as: :json
  end

  it 'lista os canais visíveis com não-lidas e se a pessoa participa' do
    time = create(:team, account: account, name: 'recepção')
    create(:team_member, team: time, user: gabriela)
    enviar(direto, eduardo)
    get url, headers: brenda.create_new_auth_token, as: :json
    canais = response.parsed_body['payload']
    expect(canais.map { |c| c['tipo'] }).to contain_exactly('geral', 'direto')
    expect(canais.find { |c| c['tipo'] == 'direto' }).to include('nome' => eduardo.name, 'nao_lidas' => 1, 'participante' => true)
    expect(response.parsed_body['admin']).to be(false)
  end

  it 'participante do 1:1 envia e lê; marcar lido zera as não-lidas' do
    enviar(direto, eduardo, '  bom dia  ')
    expect(response.parsed_body).to include('conteudo' => 'bom dia', 'autor' => include('id' => eduardo.id))
    ler_canal(direto, brenda)
    expect(response.parsed_body['payload'].pluck('conteudo')).to eq(['bom dia'])
    post "#{url}/#{direto.id}/ler", headers: brenda.create_new_auth_token, as: :json
    expect(ChatCanal.find(direto.id).nao_lidas(brenda)).to eq(0)
  end

  it 'administrador lê o 1:1 alheio, não escreve nele e marcar lido não o torna membro' do
    enviar(direto, eduardo)
    ler_canal(direto, admin)
    expect(response.parsed_body['payload'].size).to eq(1)
    enviar(direto, admin)
    expect(response).to have_http_status(:unauthorized)
    post "#{url}/#{direto.id}/ler", headers: admin.create_new_auth_token, as: :json
    expect(direto.membros.pluck(:user_id)).to contain_exactly(brenda.id, eduardo.id)
  end

  it 'quem está fora do canal não lê nem escreve' do
    ler_canal(direto, gabriela)
    expect(response).to have_http_status(:unauthorized)
    enviar(direto, gabriela)
    expect(response).to have_http_status(:unauthorized)
    expect(direto.mensagens.count).to eq(0)
  end

  it 'canal de setor: só membros do time escrevem' do
    time = create(:team, account: account, name: 'advogados')
    create(:team_member, team: time, user: brenda)
    ChatCanal.garantir_fixos!(account)
    setor = ChatCanal.find_by!(chave: "setor:#{time.id}")
    enviar(setor, brenda)
    expect(response).to have_http_status(:success)
    enviar(setor, gabriela)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'mensagem em branco não entra' do
    enviar(direto, brenda, '   ')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(direto.mensagens.count).to eq(0)
  end

  it 'abrir 1:1 é idempotente e não vale consigo mesma' do
    post "#{url}/direto", params: { user_id: eduardo.id }, headers: brenda.create_new_auth_token, as: :json
    id = response.parsed_body['id']
    post "#{url}/direto", params: { user_id: brenda.id }, headers: eduardo.create_new_auth_token, as: :json
    expect(response.parsed_body['id']).to eq(id)
    post "#{url}/direto", params: { user_id: brenda.id }, headers: brenda.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'mensagens paginadas: ?antes= traz a página anterior' do
    stub_const("#{Api::V1::Accounts::RamonChatController}::POR_PAGINA", 2)
    3.times { |i| direto.mensagens.create!(autor: brenda, conteudo: "m#{i}") }
    ler_canal(direto, brenda)
    expect(response.parsed_body).to include('mais' => true)
    expect(response.parsed_body['payload'].pluck('conteudo')).to eq(%w[m1 m2])
    get "#{url}/#{direto.id}", params: { antes: response.parsed_body['payload'].first['id'] }, headers: brenda.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('conteudo')).to eq(['m0'])
  end
end
