# "Registro completo" do lead (Painel do time, KPI do SDR): tem tese, o
# contato tem CPF e data de nascimento, e há ao menos 1 nota do lead escrita
# pelo SDR do lead. Na 1ª vez que tudo isso fica verdadeiro, grava a atividade
# `registro_completo` — uma vez só, nunca apagada (o KPI compara o dia dela com
# o dia da criação do lead). Chamado onde um desses dados muda: save do lead
# (tese/contato), update do contato (CPF/nascimento) e nota nova.
module Ramon::RegistroCompleto
  module_function

  KIND = 'registro_completo'.freeze

  def verificar(lead)
    return if lead.sdr_id.blank? || lead.lead_activities.exists?(kind: KIND) || !completo?(lead)

    lead.lead_activities.create!(account: lead.account, user_id: lead.sdr_id, kind: KIND)
  end

  def completo?(lead)
    contato = lead.contact
    lead.thesis_id.present? && contato&.cpf.present? && contato.data_nascimento.present? &&
      lead.lead_notes.exists?(user_id: lead.sdr_id)
  end

  def verificar_contato(contact)
    contact.leads.open.reorder(nil).find_each { |lead| verificar(lead) }
  end
end
