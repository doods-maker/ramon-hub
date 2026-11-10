require 'rails_helper'

RSpec.describe 'Hook da esteira: aprovações', type: :request do
  let(:url) { '/public/api/v1/esteira/aprovacoes' }
  let(:headers) { { 'X-Esteira-Token' => 'segredo' } }

  around { |exemplo| with_modified_env(RAMON_ESTEIRA_APROVACOES_TOKEN: 'segredo') { exemplo.run } }

  it 'abre o pedido e devolve a resposta dada no hub' do
    post url, params: { caso: '123', ferramenta: 'advbox_criar_tarefa', entrada: { descricao: 'x' } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    pedido = RamonAprovacaoAgente.find(response.parsed_body['id'])
    expect(pedido).to have_attributes(caso: '123', status: 'pendente', entrada: { 'descricao' => 'x' })

    get "#{url}/#{pedido.id}", headers: headers
    expect(response.parsed_body['status']).to eq('pendente')

    pedido.decidir!('aprovada', nil)
    get "#{url}/#{pedido.id}", headers: headers
    expect(response.parsed_body['status']).to eq('aprovada')
  end

  it 'entrega o motivo da negativa uma vez e apaga' do
    pedido = RamonAprovacaoAgente.abrir!(caso: '123', ferramenta: 'WebFetch', entrada: {})
    pedido.decidir!('negada', nil, motivo: 'Use a tarefa que já existe')

    get "#{url}/#{pedido.id}", headers: headers
    expect(response.parsed_body).to eq('status' => 'negada', 'motivo' => 'Use a tarefa que já existe')
    get "#{url}/#{pedido.id}", headers: headers
    expect(response.parsed_body).to eq('status' => 'negada', 'motivo' => nil)
  end

  it 'avisa pelo push sem caso, ferramenta nem dado de cliente' do
    expect do
      post url, params: { caso: '123', ferramenta: 'advbox_criar_tarefa', entrada: { descricao: 'Fulano' } }, headers: headers, as: :json
    end.to have_enqueued_job(Ramon::NtfyPushJob).with(title: 'Esteira pede aprovacao', body: 'Abra Agentes no hub para responder.')
  end

  it 'entrada grande guarda o começo de cada campo, dentro do teto, para quem decide ler' do
    post url, params: { ferramenta: 'Write', entrada: { file_path: '/casos/123/peca.md', content: "INICIO #{'x' * 60_000}" } },
              headers: headers, as: :json
    entrada = RamonAprovacaoAgente.last.entrada
    expect(entrada['file_path']).to eq('/casos/123/peca.md')
    expect(entrada['content']).to start_with('INICIO xxx').and end_with('...')
    expect(entrada['aviso']).to be_present
    expect(entrada.to_json.size).to be <= RamonAprovacaoAgente::ENTRADA_MAXIMA
  end

  it 'entrada que nem encurtada cabe no teto vira só o aviso' do
    post url, params: { ferramenta: 'Outra', entrada: (1..20).to_h { |n| ["campo#{n}", 'x' * 5_000] } }, headers: headers, as: :json
    expect(RamonAprovacaoAgente.last.entrada.keys).to eq(['aviso'])
  end

  it 'entrada que não é objeto → 422, não 500' do
    expect do
      post url, params: { ferramenta: 'Bash', entrada: 'rm -rf' }, headers: headers, as: :json
    end.not_to change(RamonAprovacaoAgente, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'recusa sem token, com token errado e quando a env está vazia' do
    post url, params: { ferramenta: 'Write' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    get "#{url}/1", headers: { 'X-Esteira-Token' => 'errado' }
    expect(response).to have_http_status(:unauthorized)

    with_modified_env(RAMON_ESTEIRA_APROVACOES_TOKEN: nil) do
      post url, params: { ferramenta: 'Write' }, headers: { 'X-Esteira-Token' => '' }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
