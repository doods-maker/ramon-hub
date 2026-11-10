# Gera PDF + memória do planejamento previdenciário (botão "Gerar"); a tela consulta o estado a cada 2 s.
# Sem retry: gerar! já grava o erro no snapshot; repetir deixaria a tela presa em "gerando".
class Ramon::PlanejamentoGerarJob < ApplicationJob
  queue_as :medium
  sidekiq_options retry: false

  def perform(calculo_id)
    calculo = Calculo.find_by(id: calculo_id)
    return if calculo.nil?

    Ramon::PlanejamentoPrevidenciario.new(calculo).gerar!
  end
end
