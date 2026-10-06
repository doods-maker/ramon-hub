require 'rails_helper'

RSpec.describe Ramon::LlmUso do
  let(:account) { create(:account) }
  let(:mensagem) { instance_double(RubyLLM::Message, input_tokens: 1_000_000, output_tokens: 1_000_000) }
  # preço do deepseek-chat em config/llm_models.json: US$ 0,14 entrada + US$ 0,28 saída por milhão
  let(:deepseek) { instance_double(RubyLLM::Model::Info, input_price_per_million: 0.14, output_price_per_million: 0.28) }

  before do
    allow(RubyLLM.models).to receive(:find).and_call_original
    allow(RubyLLM.models).to receive(:find).with('deepseek-chat').and_return(deepseek)
  end

  describe '.medir' do
    it 'grava a chamada com tokens, duração e custo pela tabela de preços do RubyLLM', :aggregate_failures do
      resultado = described_class.medir(account_id: account.id, funcao: 'copiloto', provider: 'deepseek', model: 'deepseek-chat') { mensagem }

      chamada = LlmChamada.last
      expect(resultado).to eq(mensagem)
      expect(chamada).to have_attributes(account_id: account.id, funcao: 'copiloto', origem: 'real', status: 'ok',
                                         input_tokens: 1_000_000, output_tokens: 1_000_000)
      expect(chamada.duracao_ms).to be >= 0
      expect(chamada.custo_usd.to_f).to be_within(0.001).of(0.42)
    end

    it 'modelo sem preço conhecido grava custo nil' do
      described_class.medir(account_id: account.id, funcao: 'x', model: 'modelo-que-nao-existe') { mensagem }

      expect(LlmChamada.last.custo_usd).to be_nil
    end

    it 'erro da IA vira linha de erro e sobe igual', :aggregate_failures do
      expect do
        described_class.medir(account_id: account.id, funcao: 'copiloto') { raise Ramon::LlmClient::TransientError, 'timeout' }
      end.to raise_error(Ramon::LlmClient::TransientError)

      expect(LlmChamada.last).to have_attributes(status: 'erro', erro: 'timeout', input_tokens: 0)
    end

    it 'falha ao gravar nunca quebra a resposta da IA' do
      allow(LlmChamada).to receive(:create!).and_raise(ActiveRecord::ConnectionNotEstablished)

      expect(described_class.medir(account_id: account.id, funcao: 'copiloto') { 'resposta' }).to eq('resposta')
    end

    it 'lê o hash das tarefas do Captain (usage + error)' do
      described_class.medir(account_id: account.id, funcao: 'resumo') do
        { message: nil, error: 'sem chave', usage: { 'prompt_tokens' => 10, 'completion_tokens' => 2 } }
      end

      expect(LlmChamada.last).to have_attributes(input_tokens: 10, output_tokens: 2, status: 'erro', erro: 'sem chave')
    end
  end

  describe '.contexto (LlmClient chamado sem dizer a função)' do
    it 'deduz a função pelo arquivo de quem chamou' do
      expect(described_class.contexto('/app/services/ramon/coach_objecao_service.rb')).to include(funcao: 'coach_objecao')
    end

    it 'dentro de uma execução de fluxo vira função fluxo da conta do fluxo (ensaio = teste)', :aggregate_failures do
      Current.executed_by = FluxoExecucao.new(account_id: account.id, ensaio: true)

      expect(described_class.contexto('/app/services/ramon/fluxos/passos/ia.rb'))
        .to eq(funcao: 'fluxo', account_id: account.id, origem: 'teste')
    ensure
      Current.executed_by = nil
    end
  end

  it '.de_instrumentacao traduz o feature_name do Captain para a função da tela' do
    dados = described_class.de_instrumentacao(account_id: 1, feature_name: 'faq_generator', model: 'gpt-4.1-mini',
                                              metadata: { assistant_id: 7 })

    expect(dados).to include(funcao: 'documentos', model: 'gpt-4.1-mini', assistant_id: 7)
  end

  it '.registrar_mensagem grava só a mensagem do assistente (tool result não tem tokens)' do
    assistente = instance_double(RubyLLM::Message, role: :assistant, model_id: 'gpt-4.1-mini', input_tokens: 5, output_tokens: 3)
    ferramenta = instance_double(RubyLLM::Message, role: :tool)

    expect do
      described_class.registrar_mensagem(ferramenta, { account_id: account.id, funcao: 'copilot' })
      described_class.registrar_mensagem(assistente, { account_id: account.id, funcao: 'copilot' })
    end.to change(LlmChamada, :count).by(1)
    expect(LlmChamada.last).to have_attributes(funcao: 'copiloto_captain', model: 'gpt-4.1-mini', input_tokens: 5)
  end
end
