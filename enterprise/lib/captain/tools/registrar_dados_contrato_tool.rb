# Escrita interna (nada sai para o cliente): a IA grava no cadastro do lead os dados do contrato que ele informou.
# Toda a regra (campos aceitos inclusive) fica em Ramon::DadosContrato, testada no CI. No Testar so simula: dado
# pessoal nunca e gravado por la. So o lead da conversa aberta: sem lead_id, a IA nao grava dado pessoal no contato de outro
# caso da conta (revisao final F5, I1).
class Captain::Tools::RegistrarDadosContratoTool < Captain::Tools::RamonBaseTool
  description 'Grava no cadastro do lead os dados do contrato que ele informou: nome completo, CPF, endereco (CEP, rua, ' \
              'numero, complemento, bairro, cidade, UF), estado civil e profissao. Pode gravar aos poucos, so o que ' \
              'ele ja disse. Devolve o que ainda falta para o contrato. Nada e enviado ao lead.'
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

  # Todo param e dado pessoal: nada em claro no ToolRun (params e simulacao do teste).
  PARAMS_SENSIVEIS = ::Ramon::DadosContrato::CAMPOS.map(&:to_sym).freeze

  def perform(tool_context, **dados)
    return "[TESTE] gravaria no cadastro: #{::Ramon::DadosContrato.normalizar(dados).keys.join(', ')}. Nada foi gravado." if testar?(tool_context)

    lead = resolver_lead(tool_context.state)
    return SEM_LEAD if lead.blank?

    ::Ramon::DadosContrato.texto(::Ramon::DadosContrato.gravar(lead, dados))
  end

  private

  # Testar (playground, com ou sem roteiro, inclusive "Testar com o caso"): nunca grava dado pessoal.
  def testar?(tool_context)
    tool_context&.state&.dig(:source).to_s == 'playground' || tool_context&.state&.dig(:roteiro_teste).present?
  end
end
