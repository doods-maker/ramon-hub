require 'rails_helper'

RSpec.describe 'Aprovações dos agentes', type: :request do
  let(:account) { create(:account) }
  let(:eduardo) { create(:user, account: account, role: :administrator, email: 'eduardo@example.com') }
  let(:ramon) { create(:user, account: account, role: :administrator, email: 'ramon@example.com') }
  let(:intruso) { create(:user, account: account, role: :administrator, email: 'intruso@example.com') }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_aprovacoes_agente" }
  let!(:pedido) do
    RamonAprovacaoAgente.abrir!(caso: 'Fulano de Tal #123', ferramenta: 'advbox_criar_tarefa', entrada: { 'descricao' => 'dado do cliente' })
  end

  around do |exemplo|
    with_modified_env(RAMON_PAINEL_AGENTES_EMAILS: 'eduardo@example.com,ramon@example.com',
                      RAMON_AGENTES_DECISORES_EMAILS: 'eduardo@example.com') { exemplo.run }
  end

  it 'lista os pendentes para quem está na lista, dizendo se pode decidir' do
    get url, headers: eduardo.create_new_auth_token, as: :json
    expect(response.parsed_body['pode_decidir']).to be(true)
    expect(response.parsed_body['pedidos'].first).to include('id' => pedido.id, 'caso' => 'Fulano de Tal #123', 'ferramenta' => 'advbox_criar_tarefa',
                                                             'entrada' => { 'descricao' => 'dado do cliente' })
  end

  context 'with tarefa do ADVBOX' do
    before do
      Rails.cache.delete(Ramon::NomesAdvbox::CHAVE)
      RamonAprovacaoAgente.abrir!(caso: '125', ferramenta: 'mcp__advbox__advbox_criar_tarefa',
                                  entrada: { 'responsavel_id' => 5, 'tipo_tarefa_id' => 9 })
    end

    after { Rails.cache.delete(Ramon::NomesAdvbox::CHAVE) }

    it 'traz o nome de quem recebe e do tipo, a partir dos IDs' do
      allow(Ramon::AdvboxClient).to receive(:settings).and_return({ 'users' => [{ 'id' => 5, 'name' => 'Eduardo' }],
                                                                    'tasks' => [{ 'id' => 9, 'task' => 'Solicitar documentos' }] })
      get url, headers: eduardo.create_new_auth_token, as: :json
      expect(response.parsed_body['pedidos'].last['nomes']).to eq('responsavel' => 'Eduardo', 'tipo' => 'Solicitar documentos')
    end

    it 'com o ADVBOX fora, a lista continua sem os nomes' do
      allow(Ramon::AdvboxClient).to receive(:settings).and_raise(Ramon::AdvboxClient::UnavailableError)
      get url, headers: eduardo.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['pedidos'].last['nomes']).to eq({})
    end
  end

  it 'negar com motivo guarda a orientação; aprovar ignora o motivo' do
    patch "#{url}/#{pedido.id}", params: { decisao: 'negada', motivo: '  Use a tarefa que já existe ' },
                                 headers: eduardo.create_new_auth_token, as: :json
    expect(pedido.reload).to have_attributes(status: 'negada', motivo: 'Use a tarefa que já existe')

    outro = RamonAprovacaoAgente.abrir!(caso: '126', ferramenta: 'WebFetch', entrada: {})
    patch "#{url}/#{outro.id}", params: { decisao: 'aprovada', motivo: 'x' }, headers: eduardo.create_new_auth_token, as: :json
    expect(outro.reload.motivo).to be_nil
  end

  it 'barra administrador fora da lista, para ver e para decidir' do
    get url, headers: intruso.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    patch "#{url}/#{pedido.id}", params: { decisao: 'aprovada' }, headers: intruso.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(pedido.reload.status).to eq('pendente')
  end

  it 'quem só vê recebe a lista, mas não decide' do
    get url, headers: ramon.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('pode_decidir' => false)
    expect(response.parsed_body['pedidos'].first['id']).to eq(pedido.id)

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
    expect(response.parsed_body['pedidos']).to eq([])

    RamonAprovacaoAgente.abrir!(caso: '124', ferramenta: 'WebFetch', entrada: {})
    expect(RamonAprovacaoAgente.exists?(pedido.id)).to be(false)
  end
end
