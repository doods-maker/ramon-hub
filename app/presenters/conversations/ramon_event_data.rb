# FORK(ramon): a conversa que chega pelo websocket já traz o lead enxuto —
# senão a linha "Etapa · Tese · SDR" do card sumiria a cada atualização.
module Conversations::RamonEventData
  def push_data
    super.merge(ramon_lead: ramon_lead_slim)
  end
end
