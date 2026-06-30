# frozen_string_literal: true

module Ramon
  # Espelha, nos dois sentidos, a etapa do Lead e a label `fase-*` da conversa.
  # Guarda de igualdade em cada sentido evita loop: o eco da volta encontra
  # tudo igual e morre.
  class StageLabelSync
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
      return if added_fase.empty?

      target = added_fase.last
      account = conversation.account
      lead = account.leads.find_by(conversation_id: conversation.id)
      return if lead.nil?

      stage = account.lead_stages.find_by(label: target)
      return if stage.nil?

      lead.update!(lead_stage: stage) unless lead.lead_stage_id == stage.id
      set_conversation_fase(conversation, target)
    end

    # Mantém na conversa as labels não-fase + exatamente `target`. No-op se já igual.
    def self.set_conversation_fase(conversation, target)
      current = conversation.label_list
      current_fase = current.select { |l| l.to_s.start_with?(FASE_PREFIX) }
      return if current_fase == [target]

      keep = current.reject { |l| l.to_s.start_with?(FASE_PREFIX) }
      conversation.update_labels(keep + [target])
    end
  end
end
