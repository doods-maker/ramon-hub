# Lê o gasto diário por anúncio na Marketing API e grava em MetaGasto. Relê os últimos `dias` (a Meta ajusta o gasto depois).
class Ramon::MetaGastoJob < ApplicationJob
  queue_as :low

  retry_on Ramon::MetaCapi::Transitorio, wait: :polynomially_longer, attempts: 3 do |_job, erro|
    Rails.logger.warn("MetaGastoJob: #{erro.class.name} esgotou as tentativas")
  end

  def perform(dias = 7)
    return if ENV.fetch('RAMON_META_GASTO', 'off') != 'on'

    sincronizar(dias)
  end

  # Ignora a chave (o rake usa direto). Devolve o nº de linhas gravadas, ou nil se faltar configuração.
  def sincronizar(dias)
    ad_account_id = ENV['RAMON_META_AD_ACCOUNT_ID'].presence
    return if ad_account_id.nil?

    account = Account.find(ENV.fetch('RAMON_META_ACCOUNT_ID', 2))
    token = token_de(account)
    return if token.blank?

    hoje = Time.zone.today
    linhas = Ramon::MetaCapi::Insights.new(token: token, ad_account_id: ad_account_id)
                                      .por_anuncio(desde: hoje - dias.to_i, ate: hoje - 1)
    MetaGasto.gravar(account, linhas, origem: 'api')
  rescue Ramon::MetaCapi::Recusado => e
    Rails.logger.warn("MetaGastoJob: #{e.class.name} HTTP #{e.http} code #{e.codigo || '-'}")
    nil
  end

  private

  def token_de(account)
    ENV['RAMON_META_ADS_TOKEN'].presence ||
      Channel::Whatsapp.where(account_id: account.id).order(:id).first&.provider_config.to_h['api_key']
  end
end
