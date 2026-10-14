require 'rails_helper'

RSpec.describe 'Lead roteiro API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:thesis) { create(:thesis, account: account) }
  let(:novo) { account.lead_stages.find_by!(name: 'Novo') }
  let(:lead) { create(:lead, account: account, thesis: thesis, lead_stage: novo) }
  let(:base) { "/api/v1/accounts/#{account.id}/leads/#{lead.id}" }

  before do
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'tem_advogado', position: 0, titulo: 'Tem advogado',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'desqualificar', 'motivo' => 'tem advogado' },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
  end

  it 'mostra o roteiro do lead; sem tese = null' do
    get "#{base}/roteiro", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['passos'].first).to include('chave' => 'tem_advogado', 'situacao' => 'atual')

    lead.update!(thesis: nil)
    get "#{base}/roteiro", headers: agent.create_new_auth_token
    expect(response.parsed_body).to be_nil
  end

  it 'reabrir volta no passo que decidiu e descarta só as sugestões do roteiro' do
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'sim') # sem conversa: Perdido vira sugestão no Cockpit
    outra = account.copilot_suggestions.create!(lead: lead, kind: 'acao', status: 'pending', payload: { 'acao' => 'tarefa' })

    post "#{base}/reabrir_roteiro", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['passos'].first['situacao']).to eq('atual')
    expect(account.copilot_suggestions.pending.where(lead_id: lead.id)).to eq([outra])
  end

  it 'não reabre roteiro em andamento nem lead perdido' do
    post "#{base}/reabrir_roteiro", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('não está encerrado')

    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'sim')
    lead.reload.update!(lead_stage: account.lead_stages.find_by!(is_lost: true), lost_reason: 'Outro')
    post "#{base}/reabrir_roteiro", headers: agent.create_new_auth_token
    expect(response.parsed_body['error']).to include('ganho ou perdido')
    expect(Ramon::Roteiro.atual(lead.reload)[:estado]['desfecho']).to eq('desqualificado')
  end
end
