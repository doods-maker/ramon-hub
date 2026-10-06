# frozen_string_literal: true

# Espelha a tese do Lead como a etiqueta `tese-<slug>` da conversa, para filtrar
# a lista de conversas por tese. MÃO ÚNICA (lead → conversa): mexer na etiqueta
# à mão não muda a tese do lead; o próximo write do lead repõe a certa.
class Ramon::TeseLabelSync
  PREFIX = 'tese-'
  COR = '#6b7280'

  def self.label_for(thesis)
    "#{PREFIX}#{Ramon::StageSlug.slug(thesis.name)}"
  end

  # Mantém na conversa as etiquetas que não são tese-* + a tese do lead (se tiver).
  def self.apply_to_conversation(lead)
    conversation = lead.conversation
    return if conversation.nil?

    alvo = lead.thesis && label_for(lead.thesis)
    atual = conversation.label_list
    return if atual.select { |label| label.to_s.start_with?(PREFIX) } == [alvo].compact

    Ramon::StageLabelSync.ensure_label(conversation.account, alvo, COR) if alvo
    conversation.update_labels(atual.reject { |label| label.to_s.start_with?(PREFIX) } + [alvo].compact)
  end
end
