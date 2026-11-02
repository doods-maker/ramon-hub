require 'rails_helper'

RSpec.describe Ramon::Peticionamento::LerPeca do
  let(:account) { create(:account) }
  let(:arquivo) { instance_double(PeticaoArquivo, file: :anexo) }
  let(:numero_valido_trf4) { numero_com_dv('5001234', '2026', '404', '7207') }

  # monta um número CNJ com dígito verificador correto (mod 97)
  def numero_com_dv(seq, ano, jtr, orig)
    dv = format('%02d', 98 - ("#{seq}#{ano}#{jtr}#{orig}00".to_i % 97))
    "#{seq}-#{dv}.#{ano}.#{jtr[0]}.#{jtr[1, 2]}.#{orig}"
  end

  def result(content) = Ramon::LlmClient::Result.new(content: content, input_tokens: 1, output_tokens: 1)

  def stub_llm(hash) = allow(Ramon::LlmClient).to receive(:complete).and_return(result(hash.to_json))

  def ler = described_class.call(arquivo, account: account)

  before { allow(Ramon::LlmEscolha).to receive(:chave?).with('anthropic').and_return(true) }

  it 'descarta o que não passa na validação, em vez de confiar' do
    stub_llm('numero_processo' => '5001234-00.2026.4.04.7207', 'tribunal' => 'stf', 'cpf' => '123', 'tipo' => 'outro')
    expect(ler).to include('numero_processo' => nil, 'tribunal' => nil, 'cpf' => nil, 'tipo' => nil)
    expect(ler['incertos']).to include('numero_processo', 'tribunal', 'cpf')
  end

  it 'aceita número válido e deduz o tribunal por ele, ignorando o do modelo' do
    stub_llm('numero_processo' => numero_valido_trf4.delete('^0-9'), 'tribunal' => 'tjsc', 'tipo' => 'intermediaria')
    expect(ler).to include('numero_processo' => numero_valido_trf4, 'tribunal' => 'trf4', 'falhou' => false)
  end

  it 'aceita resposta com cerca de markdown' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(result("```json\n{\"titulo\":\"Réplica\"}\n```"))
    expect(ler['titulo']).to eq('Réplica')
  end

  it 'falha da API ou JSON inválido devolve falhou, sem levantar' do
    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError, 'x')
    expect(ler['falhou']).to be(true)
    allow(Ramon::LlmClient).to receive(:complete).and_return(result('não é json'))
    expect(ler['falhou']).to be(true)
  end

  it 'sem chave devolve falhou com todas as chaves vazias' do
    allow(Ramon::LlmEscolha).to receive(:chave?).with('anthropic').and_return(false)
    expect(ler).to include('falhou' => true, 'assinantes' => [], 'marcadores' => [], 'incertos' => [], 'tipo' => nil)
    expect(ler['inicial']).to include('partes' => [], 'assuntos' => [])
  end

  it 'mantém os incertos do modelo, descarta chaves desconhecidas e lê todos os assinantes' do
    stub_llm('cpf' => '123.456.789-09', 'incertos' => %w[cpf bobagem], 'extra' => 'x',
             'assinantes' => [{ 'nome' => 'Ana', 'oab' => 'OAB/SC 1' }, { 'nome' => 'Bia' }, 'lixo'])
    r = ler
    expect(r).not_to have_key('extra')
    expect(r).to include('cpf' => '12345678909', 'incertos' => ['cpf'])
    expect(r['assinantes']).to eq([{ 'nome' => 'Ana', 'oab' => 'OAB/SC 1' }, { 'nome' => 'Bia', 'oab' => nil }])
  end

  it 'chama com a chave de API, marcando dado sensível e a função de uso' do
    stub_llm({})
    ler
    expect(Ramon::LlmClient).to have_received(:complete).with(hash_including(provider: 'anthropic', model: 'claude-haiku-5-5', sensitive: true,
                                                                             funcao: 'peticao_leitura', account_id: account.id))
  end
end
