# Leitura pura no AdvBox: dossie completo do processo numa chamada so
# (processo + movimentacoes + publicacoes + tarefas + historico).
class Captain::Tools::ConsultarDossieAdvboxTool < Captain::Tools::BasePublicTool
  description 'Traz o dossie completo de um processo do AdvBox: dados do processo, ultimas movimentacoes, ' \
              'publicacoes, tarefas e historico. Use o id devolvido por buscar_processo_advbox.'
  param :processo_id, type: 'string', desc: 'Id do processo no AdvBox'

  # ponytail: teto burro de caracteres so para nao estourar o contexto num processo
  # com historico enorme. Subido de 20k para 40k em 25/07: um dossie REAL medido na
  # producao deu 17.199 chars, perto demais do teto anterior — e o corte devolve JSON
  # invalido. O deepseek-v4-pro tem 1M de contexto, entao 40k e folgado. Se comecar a
  # cortar dossie util, o upgrade e limitar por secao (tarefas/historico) em vez do
  # JSON inteiro.
  MAX_CHARS = 40_000

  def perform(_tool_context, processo_id:)
    id = Integer(processo_id.to_s, 10, exception: false)
    return 'Informe o id numerico do processo no AdvBox.' if id.nil?

    log_tool_usage('consultar_dossie_advbox', { processo_id: id })
    truncar(Ramon::AdvboxMcpService.dossie(id).to_json)
  rescue Ramon::AdvboxClient::RequestError => e
    "O AdvBox recusou a consulta (HTTP #{e.code})."
  rescue Ramon::AdvboxClient::UnavailableError
    'O AdvBox nao respondeu agora. Tente de novo em instantes.'
  end

  private

  def truncar(json)
    return json if json.length <= MAX_CHARS

    "#{json[0, MAX_CHARS]} [dossie truncado]"
  end
end
