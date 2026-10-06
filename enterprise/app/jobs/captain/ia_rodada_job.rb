# Rodada dos casos de teste da IA: 10–30 s por caso, por isso fila baixa.
# Só pega rodada ainda na fila — retry do Sidekiq não roda a mesma duas vezes.
class Captain::IaRodadaJob < ApplicationJob
  queue_as :low

  def perform(rodada_id)
    rodada = Captain::IaRodada.find_by(id: rodada_id, status: 'fila')
    return if rodada.blank?

    Captain::IaRodadaService.new(rodada).perform
  end
end
