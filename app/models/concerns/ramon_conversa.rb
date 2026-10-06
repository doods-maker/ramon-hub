# FORK(ramon): o lead da conversa, para o card da lista de conversas mostrar
# "Etapa · Tese · SDR/Closer" (jbuilder da lista e evento do websocket).
# Trazido de feat/conversa (4e136250f0) sem o resto do redesign v2.
module RamonConversa
  extend ActiveSupport::Concern

  included do
    has_one :ramon_lead, class_name: 'Lead', inverse_of: :conversation, dependent: nil
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
