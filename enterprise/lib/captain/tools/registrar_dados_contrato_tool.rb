# Escrita interna (nada sai para o cliente): a IA grava no cadastro do lead os dados do contrato que ele informou.
# Toda a regra (campos aceitos inclusive) fica em Ramon::DadosContrato, testada no CI. No Testar so simula: dado
# pessoal nunca e gravado por la.
class Captain::Tools::RegistrarDadosContratoTool < Captain::Tools::RamonBaseTool
  description 'Grava no cadastro do lead os dados do contrato que ele informou: nome completo, CPF, endereco (CEP, rua, ' \
              'numero, complemento, bairro, cidade, UF), estado civil e profissao. Pode gravar aos poucos, so o que ' \
              'ele ja disse. Devolve o que ainda falta para o contrato. Nada e enviado ao lead.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead). Sem ele, usa o caso da conversa aberta.', required: false
  param :nome, type: 'string', desc: 'Nome completo, como no documento', required: false
  param :cpf, type: 'string', desc: 'CPF (so numeros ou com pontos e traco)', required: false
  param :cep, type: 'string', desc: 'CEP', required: false
  param :rua, type: 'string', desc: 'Rua (logradouro)', required: false
  param :numero, type: 'string', desc: 'Numero da casa', required: false
  param :complemento, type: 'string', desc: 'Complemento (apto, bloco)', required: false
  param :bairro, type: 'string', desc: 'Bairro', required: false
  param :cidade, type: 'string', desc: 'Cidade', required: false
  param :uf, type: 'string', desc: 'UF (sigla do estado)', required: false
  param :estado_civil, type: 'string', desc: 'Estado civil', required: false
  param :profissao, type: 'string', desc: 'Profissao', required: false

  def perform(tool_context, lead_id: nil, **dados)
    return "[TESTE] gravaria no cadastro: #{::Ramon::DadosContrato.normalizar(dados).keys.join(', ')}. Nada foi gravado." if testar?(tool_context)

    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    ::Ramon::DadosContrato.texto(::Ramon::DadosContrato.gravar(lead, dados))
  end

  private

  # Testar (playground, com ou sem roteiro, inclusive "Testar com o caso"): nunca grava dado pessoal.
  def testar?(tool_context)
    tool_context&.state&.dig(:source).to_s == 'playground' || tool_context&.state&.dig(:roteiro_teste).present?
  end
end
