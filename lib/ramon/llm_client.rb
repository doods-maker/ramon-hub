require 'ruby_llm'

class Ramon::LlmClient
  class SensitiveProviderError < StandardError; end
  class MissingApiKeyError < StandardError; end
  class TransientError < StandardError; end

  Result = Data.define(:content, :input_tokens, :output_tokens)

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

    message = ask(provider: provider, model: model, system: system, user: user)
    Result.new(content: message.content, input_tokens: message.input_tokens,
               output_tokens: message.output_tokens)
  end

  def self.ask(provider:, model:, system:, user:)
    context = RubyLLM.context do |config|
      config.deepseek_api_key = ENV.fetch('DEEPSEEK_API_KEY', nil)
      config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
      config.openai_api_key = ENV.fetch('OPENAI_API_KEY', nil)
    end
    chat = context.chat(model: model, provider: provider.to_sym, assume_model_exists: true)
    chat.with_instructions(system).ask(user)
  rescue StandardError => e
    raise TransientError, e.message if transient?(e)

    raise
  end

  # Transitório = sem status HTTP (rede/timeout) OU 429/5xx. RubyLLM::Error expõe o
  # status via `#response.status` (ver lib/ruby_llm/error.rb da gem, v1.15.0); erros de
  # rede (timeout/conexão) escapam da ErrorMiddleware sem status.
  def self.transient?(error)
    status = extract_status(error)
    status.nil? ? network_error?(error) : (status == 429 || status >= 500)
  end

  def self.extract_status(error)
    return error.response.status if error.respond_to?(:response) && error.response.respond_to?(:status)
    return error.status if error.respond_to?(:status)

    nil
  end

  def self.network_error?(error)
    error.is_a?(Faraday::TimeoutError) || error.is_a?(Faraday::ConnectionFailed) || error.is_a?(Timeout::Error)
  end
  private_class_method :ask, :transient?, :extract_status, :network_error?
end
