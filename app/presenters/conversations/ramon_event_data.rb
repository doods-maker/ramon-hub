# FORK(ramon): a conversa que chega pelo websocket já traz o lead enxuto —
# senão a linha "Etapa · Tese · SDR" do card sumiria a cada atualização.
module Conversations::RamonEventData
  # Na caixa Equipe a não-lida é por pessoa: o broadcast (igual pra todos) não leva unread_count (ADR 0011).
  def push_data
    data = super.merge(ramon_lead: ramon_lead_slim)
    return data unless inbox&.equipe?

    data.except(:unread_count).merge(equipe_tipo: Ramon::Equipe.tipo(self), equipe_pessoas: Ramon::Equipe.pessoas_1a1(self))
  end
end
