# FORK(ramon): o que a tela de conversa do redesign v2 precisa da conversa —
# o lead (etiqueta de etapa na lista) e quem atribuiu (faixa "Atribuída a você
# por X · hh:mm" e "Atribuídas hoje" da Recepção).
module RamonConversa
  extend ActiveSupport::Concern

  included do
    has_one :ramon_lead, class_name: 'Lead', inverse_of: :conversation, dependent: nil
    before_update :registrar_atribuicao, if: -> { will_save_change_to_assignee_id? || will_save_change_to_team_id? }
  end

  private

  def registrar_atribuicao
    return if Current.user.blank?

    self.additional_attributes = (additional_attributes || {}).merge(
      'ramon_atribuicao' => { 'por_id' => Current.user.id, 'por_nome' => Current.user.name, 'em' => Time.current.iso8601 }
    )
  end
end
