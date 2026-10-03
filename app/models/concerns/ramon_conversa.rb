# FORK(ramon): o que a tela de conversa do redesign v2 precisa da conversa —
# o lead (etiqueta de etapa na lista) e quem atribuiu (faixa "Atribuída a você
# por X · hh:mm" e "Atribuídas hoje" da Recepção).
module RamonConversa
  extend ActiveSupport::Concern

  included do
    has_one :ramon_lead, class_name: 'Lead', inverse_of: :conversation, dependent: nil
    before_update :registrar_atribuicao, if: -> { will_save_change_to_assignee_id? || will_save_change_to_team_id? }
  end

  # Bloco slim do lead (etiqueta de etapa na lista) — jbuilder e websocket.
  def ramon_lead_slim
    lead = ramon_lead
    lead && { id: lead.id, stage_name: lead.lead_stage&.name, stage_color: lead.lead_stage&.color, thesis_name: lead.thesis&.name }
  end

  private

  def registrar_atribuicao
    return if Current.user.blank? || !atribuiu?

    self.additional_attributes = (additional_attributes || {}).merge(
      'ramon_atribuicao' => { 'por_id' => Current.user.id, 'por_nome' => Current.user.name, 'em' => Time.current.iso8601 }
    )
  end

  # Só conta quando alguém (agente ou time) passa a ser o responsável por outra
  # pessoa: tirar o agente ou o time ("Devolver") e pegar a conversa pra si não contam.
  def atribuiu?
    outro_agente = will_save_change_to_assignee_id? && assignee_id.present? && assignee_id != Current.user.id
    outro_agente || (will_save_change_to_team_id? && team_id.present?)
  end
end
