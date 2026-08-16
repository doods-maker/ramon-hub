# Leitura pura no AdvBox: as publicacoes (diario oficial) de um processo,
# resumidas para o agente comentar com o cliente ou o atendente.
class Captain::Tools::PublicacoesAdvboxTool < Captain::Tools::BasePublicTool
  description 'Ultimas publicacoes de um processo no AdvBox (data e trecho). Use depois de achar o processo com ' \
              'buscar_processo_advbox, quando perguntarem se saiu algo novo no processo.'
  param :processo_id, type: 'integer', desc: 'Id do processo no AdvBox'
  param :limite, type: 'integer', desc: 'Quantas publicacoes (padrao 5, maximo 20)', required: false

  PADRAO = 5
  TETO = 20
  TRECHO = 400

  def perform(_tool_context, processo_id:, limite: nil)
    id = Integer(processo_id.to_s, exception: false)
    return 'Informe o processo_id (numero) do AdvBox.' if id.nil?

    limite = (Integer(limite.to_s, exception: false) || PADRAO).clamp(1, TETO)
    log_tool_usage('publicacoes_advbox', { processo_id: id, limite: limite })
    resposta = Ramon::AdvboxClient.publications(id, limit: limite)
    lista = resposta.is_a?(Hash) ? Array(resposta['data']) : Array(resposta)
    return 'Nenhuma publicacao encontrada para esse processo.' if lista.empty?

    "Publicacoes do processo #{id} (#{lista.size}):\n#{lista.map { |p| linha(p) }.join("\n")}"
  rescue Ramon::AdvboxClient::RequestError => e
    "O AdvBox recusou a consulta (HTTP #{e.code})."
  rescue Ramon::AdvboxClient::UnavailableError
    'O AdvBox nao respondeu agora. Tente de novo em instantes.'
  end

  private

  # Campos reais da API: start (data), title/type quando vem, publication (texto).
  def linha(pub)
    titulo = [pub['type'], pub['title']].compact_blank.join(' / ')
    texto = pub['publication'].to_s.gsub(/\s+/, ' ').truncate(TRECHO)
    "- #{pub['start']}#{" [#{titulo}]" if titulo.present?}: #{texto}"
  end
end
