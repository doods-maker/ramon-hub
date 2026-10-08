# Documento criado no ZapSign pelo hub para o cliente assinar no painel.
# status espelha o ZapSign: pendente | signed | refused; cancelado = cancelado pelo hub.
class PortalAssinatura < ApplicationRecord
  belongs_to :portal_cliente
  delegate :account, to: :portal_cliente # B5: o Disparo dos fluxos lê alvo.account

  validates :doc_token, presence: true, uniqueness: true

  scope :pendentes, -> { where(status: 'pendente') }

  def sign_url = "https://app.zapsign.com.br/verificar/#{signer_token}"
end
