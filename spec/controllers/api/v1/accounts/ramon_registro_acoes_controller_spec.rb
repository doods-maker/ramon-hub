require 'rails_helper'

RSpec.describe 'Ramon Registro de ações API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana Gestora') }
  let(:agente) { create(:user, account: account, role: :agent, name: 'Bruno SDR') }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_registro_acoes" }
  let(:qualificacao) { create(:lead_stage, account: account, name: 'Qualificação', position: 1) }
  let(:negociacao) { create(:lead_stage, account: account, name: 'Negociação', position: 2) }
  let(:contato) { create(:contact, account: account, name: 'Maria Souza') }
  let!(:lead) { create(:lead, account: account, name: 'Maria — auxílio-acidente', contact: contato, lead_stage: qualificacao) }

  def listar(params = {}, user = admin)
    get url, params: params, headers: user.create_new_auth_token, as: :json
    response.parsed_body
  end

  before do
    Audited.audit_class.as_user(admin) { lead.update!(lead_stage: negociacao) }
    Audited.audit_class.as_user(agente) { create(:conversation, account: account, contact: contato).update!(assignee: agente) }
  end

  it 'gestor vê quem fez o quê, com nomes no lugar dos ids', :aggregate_failures do
    registros = listar['registros']
    linha = registros.find { |registro| registro['modelo'] == 'Lead' }

    expect(registros.pluck('tipo')).to include('lead', 'conversa')
    expect(linha['quem']).to eq('id' => admin.id, 'nome' => 'Ana Gestora')
    expect(linha['mudancas']['lead_stage_id']).to eq(%w[Qualificação Negociação])
    expect(linha['alvo']).to include('lead_id' => lead.id, 'contato_id' => contato.id)
    expect(registros.find { |registro| registro['modelo'] == 'Conversation' }['mudancas']).to eq('assignee_id' => [nil, 'Bruno SDR'])
  end

  it 'agente não vê o registro' do
    get url, headers: agente.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'filtra por tipo, pessoa, nome e período', :aggregate_failures do
    expect(listar(tipo: 'conversa')['registros'].pluck('modelo')).to eq(['Conversation'])
    expect(listar(user_id: agente.id)['registros'].pluck('modelo')).to eq(['Conversation'])
    expect(listar(q: 'souza')['total']).to eq(2)
    expect(listar(q: 'auxílio')['registros'].pluck('modelo')).to eq(['Lead'])
    expect(listar(desde: 1.day.from_now.to_date.iso8601)['total']).to eq(0)
    expect(listar(ate: 1.day.from_now.to_date.iso8601, q: 'souza')['total']).to eq(2)
  end

  it 'pagina de 50 em 50 e exporta tudo com todos=1', :aggregate_failures do
    50.times do
      Audited.audit_class.create!(auditable: lead, associated: account, action: 'update', audited_changes: { 'value' => %w[100.0 200.0] })
    end

    expect(listar(tipo: 'lead')['registros'].size).to eq(50)
    expect(listar(tipo: 'lead', page: 2)['registros'].size).to eq(1)
    expect(listar(tipo: 'lead')['total']).to eq(51)
    expect(listar(tipo: 'lead', todos: 1)['registros'].size).to eq(51)
  end

  it 'acesso: mostra a troca de papel e esconde a disponibilidade', :aggregate_failures do
    account_user = agente.account_users.first
    [{ 'role' => [0, 1] }, { 'availability' => [0, 1] }].each do |mudancas|
      Audited.audit_class.create!(auditable: account_user, associated: account, action: 'update', audited_changes: mudancas)
    end

    registros = listar(tipo: 'acesso')['registros']
    expect(registros.map { |registro| registro['mudancas'].keys }).to include(['role'])
    expect(registros.map { |registro| registro['mudancas'].keys }).not_to include(['availability'])
    expect(registros.find { |registro| registro['mudancas'].key?('role') }['alvo']).to eq('nome' => 'Bruno SDR')
  end

  it 'a anonimização continua funcionando e aparece com o contato já anonimizado', :aggregate_failures do
    delete "/api/v1/accounts/#{account.id}/contacts/#{contato.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)

    linha = listar(tipo: 'contato')['registros'].first
    expect(linha).to include('comentario' => 'anonimizado', 'quem' => { 'id' => admin.id, 'nome' => 'Ana Gestora' })
    expect(linha['alvo']).to eq('contato_id' => contato.id, 'nome' => "Titular anonimizado ##{contato.id}")
  end
end
