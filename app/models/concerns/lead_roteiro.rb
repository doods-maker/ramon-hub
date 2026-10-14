# Leituras do roteiro da tese e do modo da IA no lead — fonte única para Ramon::CopilotoLimite,
# Ramon::ContratoAutomatico e Ramon::Roteiro::Efeitos (F5, revisão integrada item 13).
module LeadRoteiro
  extend ActiveSupport::Concern

  # Modo efetivo da IA na conversa do lead (Ramon::CopilotoModo.of: atributo → caixa → env); nil = lead sem conversa.
  def copiloto_modo
    conversation && Ramon::CopilotoModo.of(conversation)
  end

  def contrato_enviado?
    custom_attributes&.dig('zapsign', 'sign_url').present?
  end

  def desfecho_roteiro
    custom_attributes&.dig('roteiro', 'desfecho')
  end

  # Nome do signatário do contrato: o do contato, senão o do lead — 2 palavras ou mais (Ramon::ContratoAutomatico).
  def nome_completo?
    (contact&.name.presence || name).to_s.split.size >= 2
  end
end
