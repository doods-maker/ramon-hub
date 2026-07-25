module Concerns::Agentable
  extend ActiveSupport::Concern

  def agent
    Agents::Agent.new(
      name: agent_name,
      instructions: ->(context) { agent_instructions(context) },
      tools: agent_tools,
      model: agent_model,
      temperature: temperature.to_f || 0.7,
      response_schema: agent_response_schema
    )
  end

  def agent_instructions(context = nil)
    enhanced_context = prompt_context

    if context
      state = context.context[:state] || {}
      config = state[:assistant_config] || {}
      enhanced_context = enhanced_context.merge(
        conversation: state[:conversation] || {},
        contact: config['feature_contact_attributes'].present? ? state[:contact] : nil,
        campaign: state[:campaign] || {}
      )
    end

    Captain::PromptRenderer.render(template_name, enhanced_context.with_indifferent_access)
  end

  private

  def agent_name
    raise NotImplementedError, "#{self.class} must implement agent_name"
  end

  def template_name
    self.class.name.demodulize.underscore
  end

  def agent_tools
    []  # Default implementation, override if needed
  end

  # FORK-PONTO (ramon): nesta instalacao o InstallationConfig CAPTAIN_OPEN_AI_MODEL
  # NAO pertence ao Captain — ele guarda o modelo do faster-whisper local
  # (Systran/faster-whisper-medium), lido por Messages::AudioTranscriptionService via
  # Llm::LegacyBaseOpenAiService. Apontar aquele valor para um LLM de chat quebra a
  # transcricao de audio do WhatsApp. Por isso o agente ganha env propria: sem
  # RAMON_CAPTAIN_MODEL o comportamento e identico ao upstream.
  def agent_model
    ENV.fetch('RAMON_CAPTAIN_MODEL', nil).presence ||
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence ||
      LlmConstants::DEFAULT_MODEL
  end

  def agent_response_schema
    Captain::ResponseSchema
  end

  def prompt_context
    raise NotImplementedError, "#{self.class} must implement prompt_context"
  end
end
