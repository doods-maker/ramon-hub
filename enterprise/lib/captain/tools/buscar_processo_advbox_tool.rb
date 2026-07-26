# Leitura pura no AdvBox: encontra os processos da pessoa para o agente poder
# pedir o dossie de um deles (consultar_dossie_advbox).
class Captain::Tools::BuscarProcessoAdvboxTool < Captain::Tools::BasePublicTool
  description 'Busca processos no AdvBox por nome do cliente ou CPF. Devolve id, numero e partes de cada processo.'
  param :nome, type: 'string', desc: 'Nome (parcial) do cliente', required: false
  param :cpf, type: 'string', desc: 'CPF do cliente, com ou sem pontuacao', required: false

  LIMITE = 10

  def perform(_tool_context, nome: nil, cpf: nil)
    filtros = montar_filtros(nome, cpf)
    return 'Informe o nome ou o CPF para buscar.' if filtros.empty?

    log_tool_usage('buscar_processo_advbox', { filtros: filtros.keys })
    lista = extrair_lista(Ramon::AdvboxClient.lawsuits(filtros.merge(limit: LIMITE)))
    return 'Nenhum processo encontrado no AdvBox.' if lista.blank?

    lista.to_json
  rescue Ramon::AdvboxClient::RequestError => e
    "O AdvBox recusou a consulta (HTTP #{e.code})."
  rescue Ramon::AdvboxClient::UnavailableError
    'O AdvBox nao respondeu agora. Tente de novo em instantes.'
  end

  private

  # A API do AdvBox NAO devolve um Array: devolve o envelope
  # {offset, limit, totalCount, data, query}. Uma busca sem resultado traz `data` vazio
  # dentro de um Hash que NAO e blank? — sem extrair a lista, a mensagem de "nenhum
  # processo" nunca dispararia e o modelo receberia um envelope vazio para interpretar
  # (com risco de afirmar que encontrou algo). Verificado contra a API real em 25/07.
  def extrair_lista(resposta)
    return resposta if resposta.is_a?(Array)
    return [] unless resposta.is_a?(Hash)

    Array(resposta['data'] || resposta[:data])
  end

  def montar_filtros(nome, cpf)
    filtros = {}
    digitos = cpf.to_s.delete('^0-9')
    filtros[:identification] = digitos if digitos.present?
    filtros[:name] = nome if nome.present?
    filtros
  end
end
