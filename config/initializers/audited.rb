# configuration related audited gem : https://github.com/collectiveidea/audited

Audited.config do |config|
  config.audit_class = 'Enterprise::AuditLog'
end

# FORK(ramon): Registro de ações — "quem fez" também fora do login devise. O
# Sweeper do audited só vê o current_user do devise; token de API
# (Current.user = @resource) e jobs que definem Current.user (BulkActionsJob:
# atribuição em massa) ficariam sem autor. Fora disso, sem autor = automação.
module RamonAuditadoPor
  private

  def set_audit_user
    super
    self.user ||= Current.user
    nil
  end
end

ActiveSupport.on_load(:active_record) { Audited::Audit.prepend(RamonAuditadoPor) }
