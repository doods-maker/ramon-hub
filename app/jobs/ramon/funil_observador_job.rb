# Observador da conversa (funil automático): cada mensagem pública do lead aberto agenda este job com 10 min de espera;
# só o último da rajada roda (debounce). Peças todas off = não gasta LLM.
class Ramon::FunilObservadorJob < ApplicationJob
  queue_as :low
  # Esgotadas as tentativas: log + rastreio e descarta — o retry do Sidekiq pagaria o LLM de novo a cada vez.
  retry_on Ramon::LlmClient::TransientError, wait: :polynomially_longer, attempts: 3 do |job, erro|
    Rails.logger.warn("[FunilObservadorJob] #{erro.class} esgotou as tentativas message=#{job.arguments.first}")
    ChatwootExceptionTracker.new(erro).capture_exception
  end

  # Só as peças de IA já implementadas pelo observador (cada fase acrescenta as suas): peça sem efeito não paga LLM.
  OBSERVADOR_PECAS = %w[etapa_ia perdido_recusa temperatura].freeze
  ESPERA = 10.minutes

  # Temperatura em ensaio não grava nada (Aplicar#gravar_temperatura): só conta ligada.
  def self.ativo?(account)
    OBSERVADOR_PECAS.any? do |peca|
      modo = Ramon::FunilAutomatico.modo(account, peca)
      peca == 'temperatura' ? modo == 'on' : modo != 'off'
    end
  end

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank?

    lead = message.account.leads.find_by(conversation_id: message.conversation_id)
    return if lead.blank? || lead.won_at.present? || lead.lost_at.present?
    return if superada?(message) || !self.class.ativo?(lead.account)

    observar(lead)
  end

  private

  def superada?(message)
    message.conversation.messages.where(message_type: %i[incoming outgoing], private: false).exists?(['id > ?', message.id])
  end

  # Erro que não é transitório não re-tenta: o Sidekiq pagaria o LLM de novo. Log sem texto de mensagem (LGPD).
  def observar(lead)
    Ramon::FunilObservador.new(lead).perform
  rescue Ramon::LlmClient::TransientError
    raise
  rescue StandardError => e
    Rails.logger.warn("[FunilObservadorJob] #{e.class} lead=#{lead.id}")
    ChatwootExceptionTracker.new(e, account: lead.account).capture_exception
  end
end
