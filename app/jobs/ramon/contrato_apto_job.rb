# Contrato apto (Ramon::ContratoApto): de hora em hora, o contrato limpo entra na fila do jurídico e o prazo de
# 5 dias úteis vencido vira apto. Roda depois do Ramon::ContratoLimpoJob (minuto 10).
class Ramon::ContratoAptoJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Ramon::ContratoApto.rodar!
  end
end
