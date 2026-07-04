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
        allow(chat).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: 'ok'))
        result = described_class.complete(provider: 'anthropic', model: 'claude-haiku-4-5-20251001',
                                           system: 's', user: 'u', sensitive: true)
        expect(result).to eq('ok')
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
end
