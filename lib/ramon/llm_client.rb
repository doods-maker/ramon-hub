require 'ruby_llm'

class Ramon::LlmClient
  class SensitiveProviderError < StandardError; end
  class MissingApiKeyError < StandardError; end

  SENSITIVE_OK_PROVIDERS = %w[anthropic openai].freeze
  PROVIDER_ENV_KEYS = {
    'deepseek' => 'DEEPSEEK_API_KEY',
    'anthropic' => 'ANTHROPIC_API_KEY',
    'openai' => 'OPENAI_API_KEY'
  }.freeze

  def self.complete(provider:, model:, system:, user:, sensitive: false)
    if sensitive && SENSITIVE_OK_PROVIDERS.exclude?(provider)
      raise SensitiveProviderError, "Agente sensível (LGPD): provider #{provider} não autorizado"
    end

    env_key = PROVIDER_ENV_KEYS.fetch(provider)
    api_key = ENV.fetch(env_key, nil)
    raise MissingApiKeyError, "ENV #{env_key} ausente" if api_key.blank?

    context = RubyLLM.context do |config|
      config.deepseek_api_key = ENV.fetch('DEEPSEEK_API_KEY', nil)
      config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
      config.openai_api_key = ENV.fetch('OPENAI_API_KEY', nil)
    end
    chat = context.chat(model: model, provider: provider.to_sym, assume_model_exists: true)
    chat.with_instructions(system).ask(user).content
  end
end
