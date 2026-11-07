# Lê do Instagram o desempenho das peças publicadas nos últimos JANELA dias (alcance, salvamentos...).
# Desligado até o Tech Provider (RAMON_IG_INSIGHTS=on); erro numa peça não para as outras.
class Ramon::PecaMetricasJob < ApplicationJob
  queue_as :low

  JANELA = 60.days

  def perform
    return if ENV.fetch('RAMON_IG_INSIGHTS', 'off') != 'on'

    Peca.where(status: 'publicado').where.not(ig_media_id: nil).where(agendado_para: JANELA.ago..).find_each do |peca|
      metricas = Ramon::InstagramPublisher.new(peca).metricas(peca.ig_media_id)
      peca.update_columns(metricas.merge(metricas_em: Time.current)) # rubocop:disable Rails/SkipsModelValidations
    rescue StandardError => e # Meta recusou, rede, timeout: loga e segue para a próxima peça
      Rails.logger.warn("PecaMetricasJob: peça #{peca.id}: #{e.class.name} #{e.message}")
    end
  end
end
