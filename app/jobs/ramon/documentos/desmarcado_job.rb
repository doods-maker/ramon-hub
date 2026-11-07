# Documento desmarcado de um lead que já está no Jurídico (Ramon::Documentos::Passagem.avisar_desmarcado). Fora do after_commit:
# quem desmarcou na tela não toma erro se o aviso falhar.
class Ramon::Documentos::DesmarcadoJob < ApplicationJob
  queue_as :default

  def perform(lead_id, item_ids, user_id)
    lead = Lead.find_by(id: lead_id)
    Ramon::Documentos::Passagem.avisar_desmarcado(lead, item_ids, User.find_by(id: user_id)) if lead
  end
end
