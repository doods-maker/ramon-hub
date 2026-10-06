require 'rails_helper'

RSpec.describe Captain::IaRodadaService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:rodada) { Captain::IaRodada.create!(account: account, assistant: assistant, total: 2) }
  let(:runner) { instance_double(Captain::Assistant::AgentRunnerService) }
  let!(:humano) { criar_caso('A11', 'quero falar com o Dr. Ramon', 'handoff' => 'sim') }
  let!(:preco) { criar_caso('A5', 'quanto vocês cobram?', 'nao_pode_conter' => ['desconto']) }

  def criar_caso(titulo, fala, criterios, ativo: true)
    Captain::IaCaso.create!(account: account, assistant: assistant, titulo: titulo, codigo: titulo, ativo: ativo,
                            criterios: criterios, mensagens: [{ role: 'user', content: fala }])
  end

  # O runner de verdade chama on_tool_complete com o nome do RubyLLM ("captain-tools-x").
  def stub_runner(respostas)
    allow(Captain::Assistant::AgentRunnerService).to receive(:new) do |**kwargs|
      allow(runner).to receive(:generate_response) do |message_history:|
        fala = message_history.last[:content]
        ferramenta, resposta = respostas.fetch(fala)
        kwargs[:callbacks][:on_tool_complete].call("captain-tools-#{ferramenta}", '[TESTE] faria x()', nil) if ferramenta
        resposta
      end
      runner
    end
  end

  it 'roda os casos ativos em modo teste, avalia e grava o resultado de cada um', :aggregate_failures do
    criar_caso('X', 'inativo', {}, ativo: false)
    stub_runner('quero falar com o Dr. Ramon' => ['handoff', { 'response' => 'Alguém vai te chamar.', 'handoff_tool_called' => true }],
                'quanto vocês cobram?' => [nil, { 'response' => 'Te dou um desconto!' }])

    described_class.new(rodada).perform

    expect(Captain::Assistant::AgentRunnerService).to have_received(:new).with(hash_including(assistant: assistant, source: 'teste')).twice
    expect(rodada.reload).to have_attributes(status: 'concluida', total: 2, passou: 1, falhou: 1)
    por_caso = rodada.resultados.index_by { |item| item['caso_id'] }
    expect(por_caso[humano.id]).to include('passou' => true, 'handoff' => true,
                                           'ferramentas' => [{ 'nome' => 'handoff', 'resultado' => '[TESTE] faria x()' }])
    expect(por_caso[preco.id]).to include('passou' => false, 'motivos' => ['Disse o proibido: desconto'], 'resposta' => 'Te dou um desconto!')
    expect(rodada.duracao_ms).to be >= 0
  end

  it 'grava o progresso a cada caso' do
    stub_runner('quero falar com o Dr. Ramon' => [nil, { 'response' => 'oi' }], 'quanto vocês cobram?' => [nil, { 'response' => 'oi' }])
    progresso = []
    allow(rodada).to receive(:update!).and_wrap_original do |original, attrs|
      original.call(attrs).tap { progresso << rodada.resultados.size if attrs.key?(:resultados) }
    end

    described_class.new(rodada).perform

    expect(progresso).to eq([0, 1, 2])
  end

  it 'erro do agente reprova o caso sem contar como handoff' do
    stub_runner('quero falar com o Dr. Ramon' => [nil, { 'response' => 'conversation_handoff', 'reasoning' => 'Error occurred: boom' }],
                'quanto vocês cobram?' => [nil, { 'response' => 'ok' }])

    described_class.new(rodada).perform

    item = rodada.reload.resultados.find { |resultado| resultado['caso_id'] == humano.id }
    expect(item).to include('passou' => false, 'handoff' => false, 'motivos' => ['Erro do agente: Error occurred: boom'])
  end

  it 'caso que passa do tempo reprova e a rodada segue' do
    stub_runner('quero falar com o Dr. Ramon' => [nil, { 'response' => 'oi' }], 'quanto vocês cobram?' => [nil, { 'response' => 'oi' }])
    allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

    described_class.new(rodada).perform

    expect(rodada.reload).to have_attributes(status: 'concluida', falhou: 2)
    expect(rodada.resultados.first['motivos']).to eq(["Passou de #{described_class::TIMEOUT_CASO}s"])
  end

  it 'falha inesperada marca a rodada como erro (libera o assistente)' do
    allow(Captain::IaAvaliadorService).to receive(:new).and_raise(ActiveRecord::ConnectionTimeoutError, 'sem conexao')
    stub_runner('quero falar com o Dr. Ramon' => [nil, { 'response' => 'oi' }], 'quanto vocês cobram?' => [nil, { 'response' => 'oi' }])

    described_class.new(rodada).perform

    expect(rodada.reload).to have_attributes(status: 'erro')
    expect(rodada.erro).to include('sem conexao')
  end

  describe Captain::IaRodadaJob do
    it 'so roda rodada que ainda esta na fila' do
      allow(Captain::IaRodadaService).to receive(:new).and_call_original
      rodada.update!(status: 'rodando')

      described_class.perform_now(rodada.id)

      expect(Captain::IaRodadaService).not_to have_received(:new)
    end
  end
end
