# Trilha de auditoria do Painel do Cliente no hub: quem (user) fez o quê (acao)
# em qual cliente. Sem FK nem dependent: o "excluiu" sobrevive à exclusão.
class PortalEvento < ApplicationRecord
  ACOES = %w[convidou nova_senha suspendeu reativou excluiu alterou_email salvou_recado enviou_assinatura cancelou_assinatura].freeze

  belongs_to :portal_cliente, optional: true
  belongs_to :user, optional: true

  validates :acao, inclusion: { in: ACOES }
end
