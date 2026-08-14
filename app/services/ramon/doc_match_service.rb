# Anexo (imagem/arquivo) chega numa conversa com lead + checklist de docs
# pendente → pergunta ao LLM qual item do checklist o arquivo provavelmente é
# (deepseek sem visão: a pista é nome do arquivo + tipo + fim da conversa).
# Grava a sugestão em custom_attributes['doc_sugestao']; confirmação humana
# fica pro painel (Task 6).
class Ramon::DocMatchService
  PROVIDER = 'deepseek'.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você recebe um checklist de documentos de um caso previdenciário, os dados de um
    arquivo que o cliente acabou de enviar e o fim da conversa. Aponte QUAL item do
    checklist o arquivo provavelmente é. Responda APENAS um JSON válido (sem markdown):
    {"item_id": <id do item>} ou {"item_id": null} se não der pra afirmar.
    Na dúvida, responda null — nunca chute.
  PROMPT

  def initialize(message)
    @message = message
  end

  def perform
    lead = @message.account.leads.find_by(conversation_id: @message.conversation_id)
    return if lead.blank? || lead.thesis_id.blank? || attachment.blank?

    itens = pendentes(lead)
    return if itens.empty?

    item_id = ask_llm(lead, itens, attachment)
    return unless item_valido?(item_id, itens)

    gravar_sugestao(lead, item_id, attachment)
  end

  private

  def attachment
    @attachment ||= @message.attachments.detect { |a| %w[image file].include?(a.file_type) }
  end

  def item_valido?(item_id, itens)
    return false if item_id.blank?
    return true if itens.any? { |i| i.id == item_id }

    Rails.logger.info("[Ramon::DocMatchService] item_id=#{item_id} fora do checklist pendente, message=#{@message.id}")
    false
  end

  def pendentes(lead)
    status = lead.custom_attributes&.dig('doc_status') || {}
    lead.thesis.thesis_items.where(section: 'documento').reject { |i| status[i.id.to_s] == 'recebido' }
  end

  def ask_llm(lead, itens, attachment)
    checklist = itens.map { |i| "#{i.id}: #{i.title.presence || i.content}" }.join("\n")
    filename = Ramon::Pseudonymizer.mask(attachment.file.filename.to_s, names: [lead.contact&.name].compact)
    arquivo = "arquivo: #{filename} (#{attachment.file.content_type})"
    conversa = Ramon::Pseudonymizer.mask(transcript(lead), names: [lead.contact&.name].compact)
    result = Ramon::LlmClient.complete(
      provider: PROVIDER, model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'),
      system: SYSTEM_PROMPT,
      user: "Checklist:\n#{checklist}\n\n#{arquivo}\n\nFim da conversa:\n#{conversa}"
    )
    parse_item_id(result.content)
  end

  # DeepSeek roda sem json_schema — nada garante item_id numérico no wire (hábito
  # comum de LLM é devolver "42" string). Integer(..., exception: false) aceita
  # ambos e descarta silenciosamente qualquer outra coisa (null incluso) como nil.
  def parse_item_id(content)
    parsed = JSON.parse(content.to_s.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, ''))
    return nil unless parsed.is_a?(Hash)

    Integer(parsed['item_id'].to_s, exception: false)
  rescue JSON::ParserError
    Rails.logger.warn("[Ramon::DocMatchService] resposta não-JSON do LLM para message=#{@message.id}")
    nil
  end

  def transcript(lead)
    lead.conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
        .order(:created_at).last(10)
        .filter_map { |m| m.content_for_llm.presence }
        .reject { |t| t == '[Attachment]' }.join("\n")
  end

  def gravar_sugestao(lead, item_id, attachment)
    lead.reload # padrão advbox: merge sobre o estado atual, só a chave nova
    lead.update!(custom_attributes: lead.custom_attributes.to_h.merge(
      'doc_sugestao' => { 'item_id' => item_id, 'attachment_id' => attachment.id,
                          'message_id' => @message.id, 'em' => Time.zone.now.iso8601,
                          'resolvida' => false }
    ))
  end
end
