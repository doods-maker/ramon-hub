# Arquivo que o cliente subiu pelo painel para um item pedido (tarefa ADVBOX
# "SOLICITAR DOCUMENTOS" = solicitacao_post_id). O job leva pro Drive e abre
# a tarefa "ANALISAR DOCUMENTAÇÃO ENVIADA PELO CLIENTE" (advbox_post_id).
class PortalEnvio < ApplicationRecord
  belongs_to :portal_cliente
  has_one_attached :arquivo

  validates :item, presence: true
end
