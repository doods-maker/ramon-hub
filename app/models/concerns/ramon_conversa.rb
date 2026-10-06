# FORK(ramon): o lead da conversa, para o card da lista de conversas mostrar
# "Etapa · Tese · SDR/Closer" (jbuilder da lista e evento do websocket).
# Trazido de feat/conversa (4e136250f0) sem o resto do redesign v2.
module RamonConversa
  extend ActiveSupport::Concern

  included do
    has_one :ramon_lead, class_name: 'Lead', inverse_of: :conversation, dependent: nil
    # Registro de ações: atribuição/transferência (quem fez = usuário do
    # request ou Current.user, ver config/initializers/audited.rb). Roda antes
    # do Enterprise::Audit::Conversation (include_mod_with no fim do model), que
    # vira no-op — o audited só aceita uma chamada; por isso o :destroy dele vem aqui.
    audited only: %w[assignee_id team_id], on: [:update, :destroy], associated_with: :account
  end

  # Bloco enxuto do lead: o que o card precisa, nada mais.
  def ramon_lead_slim
    lead = ramon_lead
    return if lead.nil?

    {
      id: lead.id,
      stage_name: lead.lead_stage&.name, stage_color: lead.lead_stage&.color,
      thesis_name: lead.thesis&.name,
      sdr_name: lead.sdr&.name, closer_name: lead.closer&.name
    }
  end
end
