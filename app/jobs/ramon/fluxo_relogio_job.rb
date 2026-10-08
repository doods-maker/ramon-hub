# Relógio dos fluxos (a cada minuto): retoma execuções cuja espera venceu e devolve
# à fila as que ficaram 'rodando' há mais de 10 min (worker morreu no meio).
# e dispara os gatilhos do dia (relogio, lead_parado — Ramon::Fluxos::Relogio).
# e o Horário da conta (Ramon::Fluxos::HorarioConta).
# Nada fica preso em perform_in longo — deploy/reinício não perde quem esperava.
# ponytail: 500 por minuto; paginar se a fila de esperas passar disso.
class Ramon::FluxoRelogioJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    # ponytail: execução órfã (worker morreu) volta pra fila
    orfas = FluxoExecucao.where(status: 'rodando', updated_at: ..10.minutes.ago)
    orfas.update_all(status: 'esperando', retomar_em: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    FluxoExecucao.where(status: 'esperando', retomar_em: ..Time.current).order(:retomar_em).limit(500).pluck(:id)
                 .each { |id| Ramon::FluxoAvancarJob.perform_later(id) }
    Ramon::Fluxos::Relogio.disparar_do_dia
    Ramon::Fluxos::HorarioConta.disparar # B5-conta: o gatilho "Horário da conta" (rotinas da conta)
  end
end
