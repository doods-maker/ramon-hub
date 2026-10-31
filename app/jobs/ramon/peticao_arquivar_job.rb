# Arquiva o pacote protocolado no Drive (preenchido na Task 5).
class Ramon::PeticaoArquivarJob < ApplicationJob
  queue_as :low

  def perform(peticao_id); end
end
