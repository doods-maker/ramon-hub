# Relógio dos fluxos (a cada minuto): retoma execuções cuja espera venceu.
# Nada fica preso em perform_in longo — deploy/reinício não perde quem esperava.
# ponytail: 500 por minuto; paginar se a fila de esperas passar disso.
class Ramon::FluxoRelogioJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    FluxoExecucao.where(status: 'esperando', retomar_em: ..Time.current).order(:retomar_em).limit(500).pluck(:id)
                 .each { |id| Ramon::FluxoAvancarJob.perform_later(id) }
  end
end
