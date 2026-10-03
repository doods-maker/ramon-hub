# FORK(ramon): a conversa nova que chega pelo websocket já traz o lead slim
# (etiqueta de etapa na lista de conversas do redesign v2).
module Conversations::RamonEventData
  def push_data
    super.merge(ramon_lead: ramon_lead_slim)
  end
end
