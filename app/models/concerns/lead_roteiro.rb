# Leituras do roteiro da tese e do modo da IA no lead — fonte única para Ramon::CopilotoLimite,
# Ramon::ContratoAutomatico e Ramon::Roteiro::Efeitos (F5, revisão integrada item 13).
module LeadRoteiro
  extend ActiveSupport::Concern

  included do
    # Spec §3.2: trocar a tese reinicia o roteiro na hora (as respostas dos comuns ficam) — o limite dos modos e a
    # bi_roteiro leem o estado gravado, não o calculado. O modo da conversa não muda.
    before_save :reiniciar_roteiro, if: -> { persisted? && will_save_change_to_thesis_id? && custom_attributes&.key?('roteiro') }
  end

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

  private

  def reiniciar_roteiro
    estado = Ramon::Roteiro.estado(self)
    estado['passo'] = Ramon::Roteiro.proximo(Ramon::Roteiro.passos(self), estado)&.chave
    self.custom_attributes = custom_attributes.merge('roteiro' => estado)
  end
end
