# Gasto diário por anúncio na Marketing API (insights). Token no header; paging.next já vem como URL completa.
# 429/5xx/rede → Transitorio; outro 4xx → Recusado (HTTP + error.code, sem corpo).
class Ramon::MetaCapi::Insights
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 30
  CAMPOS = 'ad_id,ad_name,adset_id,adset_name,campaign_id,campaign_name,objective,spend,impressions,clicks,actions,date_start'.freeze
  # Resultados que a própria Meta conta (conferência Meta × hub).
  CONVERSA = 'onsite_conversion.messaging_conversation_started_7d'.freeze
  LEAD = 'lead'.freeze
  REDE = Ramon::MetaCapi::Cliente::REDE

  def initialize(token:, ad_account_id:)
    @token = token
    @ad_account_id = ad_account_id
  end

  def por_anuncio(desde:, ate:)
    query = { level: 'ad', time_increment: 1, fields: CAMPOS, limit: 500,
              time_range: { since: desde.to_s, until: ate.to_s }.to_json }
    url = "#{Ramon::MetaCapi.base}/act_#{@ad_account_id}/insights"
    linhas = []
    while url
      corpo = requisitar(url, query)
      linhas.concat(Array(corpo['data']).map { |l| linha(l) })
      url = corpo.dig('paging', 'next')
      query = nil
    end
    linhas
  end

  private

  def linha(item)
    { data: Date.parse(item['date_start']), ad_id: item['ad_id'], ad_name: item['ad_name'],
      adset_id: item['adset_id'], adset_name: item['adset_name'], campaign_id: item['campaign_id'], campaign_name: item['campaign_name'],
      objetivo: item['objective'], spend: BigDecimal(item['spend'].to_s.presence || '0'),
      impressions: item['impressions'].to_i, clicks: item['clicks'].to_i,
      conversas: acao(item, CONVERSA), leads_meta: acao(item, LEAD) }
  end

  def acao(item, tipo)
    Array(item['actions']).find { |a| a['action_type'] == tipo }.to_h['value'].to_i
  end

  def requisitar(url, query)
    opts = { headers: { 'Accept' => 'application/json', 'Authorization' => "Bearer #{@token}" },
             open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT }
    opts[:query] = query if query
    resposta = HTTParty.get(url, **opts)
    return resposta.parsed_response if resposta.success?
    raise Ramon::MetaCapi::Transitorio, "HTTP #{resposta.code}" if resposta.code == 429 || resposta.code >= 500

    raise Ramon::MetaCapi::Recusado.new(resposta.code, codigo_meta(resposta))
  rescue *REDE, Net::OpenTimeout, Net::ReadTimeout
    raise Ramon::MetaCapi::Transitorio, 'rede'
  end

  def codigo_meta(resposta)
    corpo = resposta.parsed_response
    corpo.is_a?(Hash) ? corpo.dig('error', 'code') : nil
  end
end
