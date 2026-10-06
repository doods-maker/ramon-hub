# == Schema Information
#
# Table name: audits
#
#  id              :bigint           not null, primary key
#  action          :string
#  associated_type :string
#  auditable_type  :string
#  audited_changes :jsonb
#  comment         :string
#  remote_address  :string
#  request_uuid    :string
#  user_type       :string
#  username        :string
#  version         :integer          default(0)
#  created_at      :datetime
#  associated_id   :bigint
#  auditable_id    :bigint
#  user_id         :bigint
#
# Indexes
#
#  associated_index              (associated_type,associated_id)
#  auditable_index               (auditable_type,auditable_id,version)
#  index_audits_on_created_at    (created_at)
#  index_audits_on_request_uuid  (request_uuid)
#  user_index                    (user_id,user_type)
#
class Enterprise::AuditLog < Audited::Audit
  # FORK(ramon): before_create (era after_save + update_columns) — audits é
  # somente-inclusão (trigger audits_somente_inclusao). Roda depois do
  # set_audit_user do audited (callback da classe-mãe vem antes).
  before_create :log_additional_information

  private

  def log_additional_information
    if auditable_type == 'Account' && auditable_id.present?
      self.associated_type = auditable_type
      self.associated_id = auditable_id
    end
    # try: o autor pode ser AgentBot (token de API), que não tem e-mail
    self.username = user_as_model.try(:email)
  end
end
