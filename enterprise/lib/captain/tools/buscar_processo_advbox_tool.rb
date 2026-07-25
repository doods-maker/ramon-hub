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
    processos = Ramon::AdvboxClient.lawsuits(filtros.merge(limit: LIMITE))
    return 'Nenhum processo encontrado no AdvBox.' if processos.blank?

    processos.to_json
  rescue Ramon::AdvboxClient::RequestError => e
    "O AdvBox recusou a consulta (HTTP #{e.code})."
  rescue Ramon::AdvboxClient::UnavailableError
    'O AdvBox nao respondeu agora. Tente de novo em instantes.'
  end

  private

  def montar_filtros(nome, cpf)
    filtros = {}
    filtros[:identification] = cpf.delete('^0-9') if cpf.present?
    filtros[:name] = nome if nome.present?
    filtros
  end
end
