class Contacts::BulkDeleteService
  def initialize(account:, contact_ids: [])
    @account = account
    @contact_ids = Array(contact_ids).compact
  end

  def perform
    return if @contact_ids.blank?

    # FORK(ramon/LGPD): anonimiza como a exclusão individual (ContactsController#destroy).
    # Cliente com contrato é pulado (o anonimizador já registrou o pedido e avisou a gestão); o lote segue.
    contacts.find_each do |contact|
      Ramon::ContactAnonymizer.new(contact, comentario: 'anonimizado_em_massa').perform
    rescue Ramon::ContactAnonymizer::ClienteGanho
      next
    end
  end

  private

  def contacts
    @account.contacts.where(id: @contact_ids)
  end
end
