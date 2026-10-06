class Contacts::BulkDeleteService
  def initialize(account:, contact_ids: [])
    @account = account
    @contact_ids = Array(contact_ids).compact
  end

  def perform
    return if @contact_ids.blank?

    # FORK(ramon/LGPD): anonimiza como a exclusão individual (ContactsController#destroy).
    contacts.find_each { |contact| Ramon::ContactAnonymizer.new(contact, comentario: 'anonimizado_em_massa').perform }
  end

  private

  def contacts
    @account.contacts.where(id: @contact_ids)
  end
end
