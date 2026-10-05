# Anda uma execução de fluxo (criada pelo Disparo ou retomada pelo relógio).
class Ramon::FluxoAvancarJob < ApplicationJob
  queue_as :default

  def perform(execucao_id)
    execucao = FluxoExecucao.find_by(id: execucao_id)
    Ramon::Fluxos::Executor.new(execucao).avancar! if execucao
  end
end
