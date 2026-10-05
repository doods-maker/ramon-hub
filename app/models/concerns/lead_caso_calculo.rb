# Casos que a tela Cálculos usa e que vivem fora do funil (source
# calculo-advbox — ver Lead.funil): o rascunho de cada usuário (cálculo rápido,
# sem contato) e o caso oculto de quem ainda não é lead comercial.
module LeadCasoCalculo
  extend ActiveSupport::Concern

  class_methods do
    # Um rascunho por usuário, reaproveitado.
    def rascunho_de!(account, user)
      account.leads.find_or_create_by!(source: Lead::FONTE_CALCULO, contact_id: nil,
                                       name: "Cálculo rápido — #{user.name}") do |novo|
        novo.lead_stage = account.lead_stages.order(:position).first
      end
    end
  end

  def caso_de_calculo?
    source == Lead::FONTE_CALCULO
  end

  def rascunho_de_calculo?
    caso_de_calculo? && contact_id.nil?
  end
end
