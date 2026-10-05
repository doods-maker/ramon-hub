# Registro de acesso ao Painel do Cliente (data/hora + IP) — Marco Civil da Internet,
# art. 15: guarda por 6 meses. Gravado a cada login e no 1º acesso de cada dia;
# o Ramon::PortalSyncJob apaga os mais velhos que PRAZO toda noite.
class PortalAcesso < ApplicationRecord
  PRAZO = 6.months

  # optional: a linha fica depois que o cliente é excluído (identificada pelo CPF).
  belongs_to :portal_cliente, optional: true

  before_create { self.cpf ||= portal_cliente&.cpf }

  def self.expurgar! = where(created_at: ...PRAZO.ago).delete_all
end
