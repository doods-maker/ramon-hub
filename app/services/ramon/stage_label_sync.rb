# frozen_string_literal: true

# Espelha, nos dois sentidos, a etapa do Lead e a label `fase-*` da conversa.
# Guarda de igualdade em cada sentido evita loop: o eco da volta encontra
# tudo igual e morre.
class Ramon::StageLabelSync
  FASE_PREFIX = 'fase-'

  # Lead -> conversa: garante que a conversa tenha exatamente a fase-* da etapa.
  def self.apply_to_conversation(lead)
    conversation = lead.conversation
    target = lead.lead_stage&.label
    return if conversation.nil? || target.blank?

    set_conversation_fase(conversation, target)
  end

  # Conversa -> lead: a fase-* adicionada (última, se várias) define a etapa.
  def self.apply_to_lead(conversation, added_labels)
    added_fase = Array(added_labels).map(&:to_s).select { |l| l.start_with?(FASE_PREFIX) }
    # Só agimos sobre fase-* ADICIONADA. Remover a única fase-* da conversa é
    # no-op de propósito (decisão do plano 2C): o lead fica onde está e o
    # self-heal repõe a label no próximo write do lead / no backfill.
    return if added_fase.empty?

    target = added_fase.last
    account = conversation.account
    lead = account.leads.find_by(conversation_id: conversation.id)
    return if lead.nil?

    stage = account.lead_stages.find_by(label: target)
    return if stage.nil?

    lead.update!(lead_stage: stage) unless lead.lead_stage_id == stage.id
    # Self-heal INCONDICIONAL (mesmo se a etapa já estava certa): garante
    # exatamente uma fase-* na conversa, removendo uma 2ª fase-* que tenha
    # chegado junto. É o que faz valer a exclusividade "a adicionada vence".
    set_conversation_fase(conversation, target)
  end

  # Mantém na conversa as labels não-fase + exatamente `target`. No-op se já igual.
  def self.set_conversation_fase(conversation, target)
    current = conversation.label_list
    current_fase = current.select { |l| l.to_s.start_with?(FASE_PREFIX) }
    return if current_fase == [target]

    ensure_label(conversation.account, target)
    keep = current.reject { |l| l.to_s.start_with?(FASE_PREFIX) }
    conversation.update_labels(keep + [target])
  end

  # Cria a Label nativa fase-* SOB DEMANDA (cor canônica + show_on_sidebar).
  # Lazy de propósito: não semeamos em toda conta para não poluir a
  # enumeração global de labels (specs nativos do Chatwoot assumem conta limpa).
  def self.ensure_label(account, title)
    account.labels.find_or_create_by!(title: title) do |label|
      label.color = Leads::SeedDefaultConfigService.color_for(title)
      label.show_on_sidebar = true
    end
  end
end
