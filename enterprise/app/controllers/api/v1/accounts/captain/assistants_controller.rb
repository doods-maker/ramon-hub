class Api::V1::Accounts::Captain::AssistantsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }

  before_action :set_assistant, only: [:show, :update, :destroy, :playground, :buscar_faq, :texto_final]

  def index
    @assistants = account_assistants.ordered
  end

  def show; end

  def create
    @assistant = account_assistants.create!(assistant_params)
  end

  def update
    @assistant.update!(assistant_params)
  end

  def destroy
    @assistant.destroy
    head :no_content
  end

  def playground
    return render(json: playground_legado) unless captain_v2_enabled?

    # ramon (I-PG2): as ferramentas que rodaram nesta resposta vão junto, para o Testar mostrar debaixo dela.
    ferramentas = []
    coletor = ->(nome, retorno, *) { ferramentas << ferramenta_usada(nome, retorno) }
    runner = Captain::Assistant::AgentRunnerService.new(assistant: @assistant, source: 'playground',
                                                        callbacks: { on_tool_complete: coletor })
    render json: runner.generate_response(message_history: playground_message_history).merge('ferramentas' => ferramentas)
  end

  def tools
    assistant = Captain::Assistant.new(account: Current.account)
    @tools = assistant.available_agent_tools
  end

  # ramon: tela Assistentes (I-AS1/I-AS2/I-AS3) — um cartão por assistente.
  # ponytail: ~5 consultas por assistente; são 2. Se passar de 10, agrupar.
  def stats
    render json: { payload: account_assistants.order(:id).map { |assistant| cartao(assistant) } }
  end

  # ramon: "Testar pergunta" (I-FQ2) — as FAQs que a ferramenta faq_lookup deste
  # assistente acharia para a pergunta, na mesma ordem (mesma busca, até 5).
  # Pergunta em branco não busca (no modo vetorial chamaria embedding à toa).
  def buscar_faq
    pergunta = params[:q].to_s.strip
    faqs = pergunta.present? ? @assistant.responses.approved.search(pergunta).to_a : []
    render json: { payload: faqs.map { |faq| faq.slice(:id, :question, :answer, :tese) } }
  end

  # ramon (I-CF6): o texto final que o assistente recebe — o dele (diretrizes, proteções e a lista de skills,
  # montados pelo liquid) e o de cada skill ligada. Só leitura.
  def texto_final
    skills = @assistant.scenarios.enabled.order(:id).map { |skill| { title: skill.title, texto: skill.agent_instructions } }
    render json: { assistente: @assistant.agent_instructions, skills: skills }
  end

  private

  def set_assistant
    @assistant = account_assistants.find(params[:id])
  end

  def playground_legado
    Captain::Llm::AssistantChatService.new(assistant: @assistant, source: 'playground').generate_response(
      additional_message: playground_params[:message_content], message_history: message_history
    )
  end

  # RubyLLM::Tool#name = "captain-tools-<id>"; erro = o aviso que o BasePublicTool devolve quando a ferramenta falha.
  def ferramenta_usada(nome, retorno)
    id = nome.to_s.split('-').last
    info = Captain::Assistant.built_in_agent_tools.find { |tool| tool[:id] == id } || {}
    { id: id, title: info[:title] || id, nivel: info[:nivel],
      status: retorno.to_s == Captain::Tools::BasePublicTool::ERRO_NA_TOOL ? 'erro' : 'ok' }
  end

  def account_assistants
    @account_assistants ||= Captain::Assistant.for_account(Current.account.id)
  end

  def cartao(assistant)
    caixas = assistant.inboxes.order(:id).pluck(:id, :name, :channel_type)
                      .map { |id, name, tipo| { id: id, name: name, channel_type: tipo } }
    {
      id: assistant.id, name: assistant.name, description: assistant.description,
      # ponytail: público pela caixa — com caixa fala com o lead; sem caixa, só pela tela Testar (equipe).
      publico: caixas.any? ? 'lead' : 'equipe',
      skills_ativas: assistant.scenarios.enabled.count,
      faqs_aprovadas: assistant.responses.approved.count, faqs_pendentes: assistant.responses.pending.count,
      caixas: caixas, conversas_por_modo: conversas_por_modo(caixas.pluck(:id))
    }
  end

  # Conversas abertas nas caixas do assistente pelo modo efetivo (como Ramon::CopilotoModo.of):
  # sem atributo ou com valor fora da lista conta no padrão do servidor.
  def conversas_por_modo(inbox_ids)
    abertas = Current.account.conversations.where(status: :open, inbox_id: inbox_ids)
    contagem = abertas.group(Arel.sql("custom_attributes->>'copiloto_modo'")).count
    contagem.each_with_object(Hash.new(0)) do |(modo, total), soma|
      soma[Ramon::CopilotoModo::MODOS.include?(modo) ? modo : Ramon::CopilotoModo.default] += total
    end
  end

  def assistant_params
    permitted = params.require(:assistant).permit(:name, :description,
                                                  config: [
                                                    :product_name, :feature_faq, :feature_memory, :feature_citation,
                                                    :feature_contact_attributes,
                                                    :welcome_message, :handoff_message, :resolution_message,
                                                    :instructions, :temperature
                                                  ])

    # Handle array parameters separately to allow partial updates
    permitted[:response_guidelines] = params[:assistant][:response_guidelines] if params[:assistant].key?(:response_guidelines)

    permitted[:guardrails] = params[:assistant][:guardrails] if params[:assistant].key?(:guardrails)

    permitted
  end

  def playground_params
    params.require(:assistant).permit(:message_content, message_history: [:role, :content, :agent_name])
  end

  def message_history
    (playground_params[:message_history] || []).map do |message|
      {
        role: message[:role],
        content: message[:content],
        agent_name: message[:agent_name]
      }.compact
    end
  end

  def playground_message_history
    history = message_history
    current_message = playground_params[:message_content]
    return history if current_message.blank?

    current_user_message = { role: 'user', content: current_message }
    return history if history.last == current_user_message

    history + [current_user_message]
  end

  def captain_v2_enabled?
    @assistant.account.feature_enabled?('captain_integration_v2')
  end
end
