class Captain::Tools::FaqLookupTool < Captain::Tools::BasePublicTool
  description 'Search FAQ responses using semantic similarity to find relevant answers'
  param :query, type: 'string', desc: 'The question or topic to search for in the FAQ database'

  def perform(tool_context, query:)
    log_tool_usage('searching', { query: query })

    # Use existing vector search on approved responses
    responses = @assistant.responses.approved.search(query).to_a

    if responses.empty?
      log_tool_usage('no_results', { query: query })
      "No relevant FAQs found for: #{query}"
    else
      contar_uso(tool_context, responses)
      log_tool_usage('found_results', { query: query, count: responses.size })
      format_responses(responses)
    end
  end

  private

  # ramon (I-FQ6): "usada X vezes" — conta só o atendimento de verdade (Testar e Casos de teste ficam de fora).
  # update_all: não mexe em updated_at nem marca a FAQ como editada.
  # ponytail: a regra "uso real = não Testar/caso de teste" também vive em SQL na consulta de uso de skills
  # (Task 4); duplicada de propósito para não tocar BasePublicTool — se mudar aqui, mude lá.
  def contar_uso(tool_context, responses)
    return if %w[playground teste].include?(tool_context&.state&.dig(:source).to_s)

    ::Captain::AssistantResponse.where(id: responses.map(&:id))
                                .update_all(['usos = usos + 1, usada_em = ?', Time.current]) # rubocop:disable Rails/SkipsModelValidations
  end

  def format_responses(responses)
    responses.map { |response| format_response(response) }.join
  end

  def format_response(response)
    formatted_response = "
        Question: #{response.question}
        Answer: #{response.answer}
        "
    if should_show_source?(response)
      formatted_response += "
          Source: #{response.documentable.external_link}
          "
    end

    formatted_response
  end

  def should_show_source?(response)
    return false if response.documentable.blank?
    return false unless response.documentable.try(:external_link)

    # Don't show source if it's a PDF placeholder
    external_link = response.documentable.external_link
    !external_link.start_with?('PDF:')
  end
end
