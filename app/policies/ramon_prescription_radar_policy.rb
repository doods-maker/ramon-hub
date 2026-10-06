# Radar de prescrição: admin + agente veem (mesma regra do Centro de Comando);
# etiquetar a base pra campanha de resgate é do gestor (a tela de campanhas
# também é só de administrador).
class RamonPrescriptionRadarPolicy < ApplicationPolicy
  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def resgate?
    @account_user.administrator?
  end
end
