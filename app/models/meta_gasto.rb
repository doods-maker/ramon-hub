# Gasto diário por anúncio vindo do Gerenciador de Anúncios da Meta: pela API (Ramon::MetaGastoJob)
# ou pelo CSV exportado (Ramon::MetaGastoCsv), que é a ponte até a API ligar. Mesmo anúncio+dia = mesma linha.
class MetaGasto < ApplicationRecord
  self.table_name = 'ramon_meta_gastos'

  COLUNAS = %i[ad_name adset_id adset_name campaign_id campaign_name objetivo spend impressions clicks conversas leads_meta].freeze

  belongs_to :account

  # Devolve o nº de linhas gravadas. updated_at fora de update_only: o upsert_all do Rails 7.1 já atualiza.
  def self.gravar(account, linhas, origem:)
    return 0 if linhas.empty?

    agora = Time.current
    registros = linhas.map do |l|
      COLUNAS.index_with { nil }.merge(l).merge(account_id: account.id, origem: origem, created_at: agora, updated_at: agora)
    end
    upsert_all(registros, unique_by: %i[account_id ad_id data], update_only: COLUNAS + [:origem]) # rubocop:disable Rails/SkipsModelValidations
    linhas.size
  end
end
