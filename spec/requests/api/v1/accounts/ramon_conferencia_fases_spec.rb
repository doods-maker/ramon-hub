require 'rails_helper'

RSpec.describe 'Conferência de fases API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/ramon_conferencia_fases" }
  let(:sugestao) { { 'etapa' => 'EXECUÇÃO COMO EXEQUENTE', 'etapa_id' => 3_949_581 } }

  def conferencia(**attrs)
    account.ramon_conferencias_fase.create!({ lawsuit_id: rand(1..999_999), grupo: 'igual', cliente: 'FULANO' }.merge(attrs))
  end

  it 'exige autenticação' do
    get base
    expect(response).to have_http_status(:unauthorized)
  end

  it 'lista filtrada por grupo e busca, com o resumo da carteira inteira' do
    conferencia(grupo: 'atrasada', cliente: 'SIEMES ELISEU LINS', numero: '5000939-49.2025.4.04.7216', sugestao: sugestao)
    conferencia(grupo: 'baixa', cliente: 'CAROLINE COMELI')
    get base, headers: agent.create_new_auth_token, params: { grupo: 'atrasada', q: '5000939' }
    expect(response.parsed_body['payload'].pluck('cliente')).to eq ['SIEMES ELISEU LINS']
    expect(response.parsed_body['resumo']['grupos']).to eq('atrasada' => 1, 'baixa' => 1)
    expect(response.parsed_body['permissoes']).to eq('aplicar' => false)
  end

  it 'a equipe marca; "atualizar" só vale com sugestão' do
    com = conferencia(grupo: 'atrasada', sugestao: sugestao)
    sem = conferencia(grupo: 'diferente')
    patch "#{base}/#{com.id}", headers: agent.create_new_auth_token, params: { painel_marca: 'errado', atualizar: true, obs: 'já em execução' }
    patch "#{base}/#{sem.id}", headers: agent.create_new_auth_token, params: { atualizar: true }
    expect(com.reload).to have_attributes(painel_marca: 'errado', atualizar: true, obs: 'já em execução', marcado_por: agent)
    expect(sem.reload.atualizar).to be false
  end

  it 'aplicar no ADVBOX: só administrador' do
    conferencia(grupo: 'atrasada', sugestao: sugestao, atualizar: true)
    post "#{base}/aplicar", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect { post "#{base}/aplicar", headers: admin.create_new_auth_token }.to have_enqueued_job(Ramon::ConferenciaAplicarJob)
    expect(response.parsed_body).to eq('enfileirados' => 1)
  end
end
