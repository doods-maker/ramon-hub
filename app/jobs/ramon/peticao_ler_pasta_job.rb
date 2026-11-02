# Lê a pasta do Drive de uma petição em conferência. Esgotadas as tentativas, marca a leitura como erro (o front mostra e deixa reler).
class Ramon::PeticaoLerPastaJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 30.seconds, attempts: 3 do |job, _erro|
    peticao = Peticao.find_by(id: job.arguments.first)
    peticao&.update_columns(leitura: (peticao.leitura || {}).merge('estado' => 'erro')) if peticao&.editavel? # rubocop:disable Rails/SkipsModelValidations
  end

  def perform(peticao_id)
    peticao = Peticao.find_by(id: peticao_id)
    return if peticao.nil? || peticao.protocolada?

    Ramon::Peticionamento::ImportarPasta.call(peticao)
  end
end
