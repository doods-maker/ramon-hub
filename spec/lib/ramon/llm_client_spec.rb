require 'rails_helper'

RSpec.describe Ramon::LlmClient do
  describe 'trava LGPD' do
    it 'bloqueia deepseek quando sensitive, ANTES de qualquer chamada' do
      expect(RubyLLM).not_to receive(:context)
      expect do
        described_class.complete(provider: 'deepseek', model: 'deepseek-chat', system: 's', user: 'u', sensitive: true)
      end.to raise_error(described_class::SensitiveProviderError)
    end

    it 'permite anthropic quando sensitive' do
      with_modified_env ANTHROPIC_API_KEY: 'k' do
        chat = instance_double(RubyLLM::Chat)
        allow(RubyLLM).to receive(:context).and_return(instance_double(RubyLLM::Context, chat: chat))
        allow(chat).to receive(:with_instructions).and_return(chat)
        message = instance_double(RubyLLM::Message, content: 'ok', input_tokens: 10, output_tokens: 5)
        allow(chat).to receive(:ask).and_return(message)
        result = described_class.complete(provider: 'anthropic', model: 'claude-haiku-4-5-20251001',
                                          system: 's', user: 'u', sensitive: true)
        expect(result.content).to eq('ok')
      end
    end
  end

  it 'falha cedo sem a API key do provider' do
    with_modified_env DEEPSEEK_API_KEY: nil do
      expect do
        described_class.complete(provider: 'deepseek', model: 'deepseek-chat', system: 's', user: 'u')
      end.to raise_error(described_class::MissingApiKeyError)
    end
  end

  describe 'retorno com usage de tokens' do
    def stub_ask(with_modified_env_key: 'k')
      with_modified_env DEEPSEEK_API_KEY: with_modified_env_key do
        chat = instance_double(RubyLLM::Chat)
        allow(RubyLLM).to receive(:context).and_return(instance_double(RubyLLM::Context, chat: chat))
        allow(chat).to receive(:with_instructions).and_return(chat)
        yield chat
      end
    end

    it 'returns a Result with content and token usage' do
      stub_ask do |chat|
        message = instance_double(RubyLLM::Message, content: 'analise', input_tokens: 120, output_tokens: 45)
        allow(chat).to receive(:ask).and_return(message)
        result = described_class.complete(provider: 'deepseek', model: 'deepseek-chat', system: 's', user: 'u')
        expect(result.content).to eq('analise')
        expect(result.input_tokens).to eq(120)
        expect(result.output_tokens).to eq(45)
      end
    end

    it 'wraps a 429 from the provider as TransientError' do
      stub_ask do |chat|
        response = instance_double(Faraday::Response, status: 429)
        allow(chat).to receive(:ask).and_raise(RubyLLM::RateLimitError.new(response, 'rate limited'))
        expect do
          described_class.complete(provider: 'deepseek', model: 'm', system: 's', user: 'u')
        end.to raise_error(Ramon::LlmClient::TransientError)
      end
    end

    it 'wraps a 5xx from the provider as TransientError' do
      stub_ask do |chat|
        response = instance_double(Faraday::Response, status: 500)
        allow(chat).to receive(:ask).and_raise(RubyLLM::ServerError.new(response, 'server error'))
        expect do
          described_class.complete(provider: 'deepseek', model: 'm', system: 's', user: 'u')
        end.to raise_error(Ramon::LlmClient::TransientError)
      end
    end

    it 'wraps a network timeout (no status) as TransientError' do
      stub_ask do |chat|
        allow(chat).to receive(:ask).and_raise(Faraday::TimeoutError, 'timeout')
        expect do
          described_class.complete(provider: 'deepseek', model: 'm', system: 's', user: 'u')
        end.to raise_error(Ramon::LlmClient::TransientError)
      end
    end

    it 'does not wrap a 400 bad request' do
      stub_ask do |chat|
        response = instance_double(Faraday::Response, status: 400)
        allow(chat).to receive(:ask).and_raise(RubyLLM::BadRequestError.new(response, 'bad request'))
        expect do
          described_class.complete(provider: 'deepseek', model: 'm', system: 's', user: 'u')
        end.to raise_error(RubyLLM::BadRequestError)
      end
    end
  end
end
