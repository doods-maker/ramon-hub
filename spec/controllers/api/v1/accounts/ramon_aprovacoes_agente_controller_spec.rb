require 'rails_helper'

RSpec.describe 'Aprovações dos agentes', type: :request do
  let(:account) { create(:account) }
  let(:eduardo) { create(:user, account: account, role: :administrator, email: 'eduardo@example.com') }
  let(:ramon) { create(:user, account: account, role: :administrator, email: 'ramon@example.com') }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_aprovacoes_agente" }
  let!(:pedido) do
    RamonAprovacaoAgente.abrir!(caso: 'Fulano de Tal #123', ferramenta: 'advbox_criar_tarefa', entrada: { 'descricao' => 'dado do cliente' })
  end

  around { |exemplo| with_modified_env(RAMON_PAINEL_AGENTES_EMAILS: 'eduardo@example.com') { exemplo.run } }

  it 'lista os pendentes para quem está na lista' do
    get url, headers: eduardo.create_new_auth_token, as: :json
    expect(response.parsed_body.first).to include('id' => pedido.id, 'caso' => 'Fulano de Tal #123', 'ferramenta' => 'advbox_criar_tarefa',
                                                  'entrada' => { 'descricao' => 'dado do cliente' })
  end

  it 'barra administrador fora da lista, para ver e para decidir' do
    get url, headers: ramon.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    patch "#{url}/#{pedido.id}", params: { decisao: 'aprovada' }, headers: ramon.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(pedido.reload.status).to eq('pendente')
  end

  it 'aprova, registra quem decidiu e apaga o dado de cliente' do
    patch "#{url}/#{pedido.id}", params: { decisao: 'aprovada' }, headers: eduardo.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)
    expect(pedido.reload).to have_attributes(status: 'aprovada', decidida_por: eduardo, entrada: {}, caso: '123')
  end

  it 'não aceita segunda resposta nem decisão desconhecida' do
    patch "#{url}/#{pedido.id}", params: { decisao: 'talvez' }, headers: eduardo.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    pedido.decidir!('negada', eduardo)
    patch "#{url}/#{pedido.id}", params: { decisao: 'aprovada' }, headers: eduardo.create_new_auth_token, as: :json
    expect(response).to have_http_status(:conflict)
    expect(pedido.reload.status).to eq('negada')
  end

  it 'pedido vencido sai da lista e é apagado no próximo pedido' do
    pedido.update!(created_at: 13.hours.ago)
    get url, headers: eduardo.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq([])

    RamonAprovacaoAgente.abrir!(caso: '124', ferramenta: 'WebFetch', entrada: {})
    expect(RamonAprovacaoAgente.exists?(pedido.id)).to be(false)
  end
end
