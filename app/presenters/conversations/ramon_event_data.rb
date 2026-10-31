# FORK(ramon): a conversa que chega pelo websocket já traz o lead enxuto —
# senão a linha "Etapa · Tese · SDR" do card sumiria a cada atualização.
module Conversations::RamonEventData
  # Na caixa Equipe a não-lida é por pessoa: o broadcast (igual pra todos) não leva unread_count (ADR 0011).
  def push_data
    data = super.merge(ramon_lead: ramon_lead_slim)
    inbox&.equipe? ? data.except(:unread_count) : data
  end
end
