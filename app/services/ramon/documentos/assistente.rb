# Assistente "Documentos" do Captain (spec Etapa Documentos §3): cria ou atualiza, idempotente pelo nome, com as instruções
# aprovadas pelo Eduardo em 07/11 (config/ramon/assistente_documentos.md, texto literal), a config técnica do assistente
# da caixa (temperatura, nome do produto, aviso de handoff...), uma skill que libera só as ferramentas da etapa e o liga à
# etapa Documentos (lead_stages.captain_assistant_id). Não liga a chave RAMON_ETAPA_DOCUMENTOS.
# Rake: ramon:documentos:assistente[account_id]. Captain é enterprise: sem ele, levanta com mensagem clara.
module Ramon::Documentos::Assistente
  NOME = 'Documentos'.freeze
  TEXTO = Rails.root.join('config/ramon/assistente_documentos.md')
  # Perfil da etapa (Ramon::PerfilIa::Tela::ETAPAS_DA_ACAO: pedir_documentos) + o que falta + a imagem do passo a passo.
  # O handoff vem sempre com o assistente.
  TOOLS = %w[documentacao_faltante solicitar_documento enviar_link_portal enviar_passo_a_passo].freeze
  # A skill é a cola técnica que dá as ferramentas ao agente (o comportamento está nas instruções aprovadas).
  SKILL = {
    title: 'Conduzir os documentos',
    description: 'Cliente com contrato assinado reunindo os documentos do caso.',
    instruction: <<~TEXTO.squish
      Veja o que falta e os alertas do caso com [O que falta no caso](tool://documentacao_faltante). Para pedir os
      documentos, use [Pedir documentos](tool://solicitar_documento) ou [Link do portal do cliente](tool://enviar_link_portal).
      Quando o cliente travar num passo, mande [Imagem do passo a passo](tool://enviar_passo_a_passo) com o tema.
    TEXTO
  }.freeze

  module_function

  def instrucoes = TEXTO.read

  # O texto aprovado em blocos (separados por linha em branco), sem mexer em nenhuma palavra.
  def blocos = instrucoes.strip.split(/\n{2,}/)

  # A descrição do Captain::Assistant vai até 255 caracteres: leva só o 1º bloco (quem é e qual é o trabalho).
  def descricao = blocos.first

  # Os demais blocos viram as regras gerais (response_guidelines), o lugar que o prompt do assistente lê em todo turno.
  def diretrizes = blocos.drop(1)

  # @return [Captain::Assistant]
  def criar_ou_atualizar!(account)
    raise 'O Captain (enterprise) não está nesta instalação: nada a criar.' unless defined?(Captain::Assistant)

    assistente = account.captain_assistants.find_or_initialize_by(name: NOME)
    config = (assistente.config || {}).merge(config_da_caixa(account)).merge('instructions' => instrucoes)
    assistente.update!(description: descricao, config: config, response_guidelines: diretrizes, guardrails: [])
    skill!(account, assistente)
    account.lead_stages.find_by(label: Ramon::EtapaDeGanho::DOCUMENTOS)&.update!(captain_assistant: assistente)
    assistente
  end

  # O assistente da 1ª caixa com IA (o de vendas): só a config técnica; as instruções são as daqui.
  def config_da_caixa(account)
    caixa = account.inboxes.order(:id).find { |inbox| inbox.try(:captain_assistant).present? }
    caixa ? caixa.captain_assistant.config.except('instructions') : {}
  end

  def skill!(account, assistente)
    skill = assistente.scenarios.find_or_initialize_by(seed_titulo: SKILL[:title])
    skill.update!(account: account, title: SKILL[:title], description: SKILL[:description], instruction: SKILL[:instruction],
                  enabled: true)
  end
end
