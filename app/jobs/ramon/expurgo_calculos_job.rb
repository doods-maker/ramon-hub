# Expurgo do histórico de cálculos SEM cliente: os cálculos feitos no caso de
# rascunho (source calculo-advbox, sem contato) guardam nome, CPF e salários de
# quem nem virou lead — somem depois de 30 dias (decisão Eduardo 24/08/2026).
# Cálculos de lead real ficam para sempre. O caso de rascunho em si não é apagado.
class Ramon::ExpurgoCalculosJob < ApplicationJob
  queue_as :scheduled_jobs

  DIAS = 30

  def perform
    rascunhos = Lead.where(source: Lead::FONTE_CALCULO, contact_id: nil).select(:id)
    Calculo.where(lead_id: rascunhos).where(created_at: ...DIAS.days.ago).delete_all
  end
end
