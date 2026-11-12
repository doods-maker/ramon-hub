# Eliminação LGPD do titular que NÃO é cliente (decisões de 12/11/2026): o que ele deixou fora do contato.
# Chamado pelo Ramon::ContactAnonymizer dentro da transação, depois da recusa do cliente.
# Texto livre é mascarado (o registro fica para a estatística); o que não tem o que preservar sai.
# Fica: meta_referral (origem de marketing), valor do lead, datas e etapas.
# Petição recusa antes (Ramon::ContactAnonymizer). Execução de fluxo de Painel, peça e chegada não é de não cliente.
# ponytail: o evento na Agenda Google da reunião (lead_tasks.google_event_id) e a FAQ já vetorizada (embedding) ficam;
# limpar à mão se o titular pedir.
# rubocop:disable Rails/SkipsModelValidations
class Ramon::RastrosDoTitular
  ATIVAS = %w[rodando esperando].freeze

  attr_reader :pastas_drive, :audios # preenchidos por perform; quem chama apaga depois do commit

  # leads: os do titular (pelo contato ou pela conversa); mask: o mascarador com os nomes do titular.
  def initialize(contact, leads, mask)
    @contact = contact
    @leads = leads
    @mask = mask
    @pastas_drive = {}
    @audios = []
  end

  def perform
    @leads.each { |lead| limpar_lead(lead) }
    limpar_conversas
    limpar_execucoes
  end

  private

  def limpar_lead(lead)
    pasta = lead.custom_attributes&.dig('drive', 'pasta_id')
    @pastas_drive[pasta] ||= lead if pasta.present?
    mascarar_registros_do_lead(lead)
    apagar_registros_do_lead(lead)
    lead.update_columns(name: "Titular anonimizado ##{@contact.id}", cnis: nil, portal_token: nil, devolvido_motivo: nil,
                        lost_reason: @mask.call(lead.lost_reason), dcb_em: nil, benefit_monthly_value: nil,
                        custom_attributes: lead.custom_attributes.to_h.slice('meta_referral'))
  end

  def mascarar_registros_do_lead(lead)
    lead.lead_notes.find_each { |nota| nota.update_columns(body: @mask.call(nota.body)) }
    lead.lead_tasks.find_each { |tarefa| tarefa.update_columns(title: @mask.call(tarefa.title), meet_url: nil) }
    lead.lead_activities.find_each { |a| a.update_columns(from_value: @mask.call(a.from_value), to_value: @mask.call(a.to_value)) }
    lead.reunioes.find_each { |reuniao| limpar_reuniao(reuniao) }
  end

  # Cálculo (CNIS inteiro no snapshot) e sugestão do copiloto (rascunho de mensagem): saem. Triagem fica com status e tokens.
  def apagar_registros_do_lead(lead)
    lead.funil_acoes.update_all(motivo: nil, desfazer: {})
    lead.calculos.delete_all
    lead.copilot_suggestions.delete_all
    lead.lead_triages.update_all(source_text: nil, result: nil, kit: nil, error_message: nil)
  end

  def limpar_reuniao(reuniao)
    @audios << reuniao.audio if reuniao.audio.attached?
    reuniao.update_columns(titulo: @mask.call(reuniao.titulo), transcricao: @mask.call(reuniao.transcricao), ata: @mask.call(reuniao.ata))
  end

  # Anexos (RG, laudo, áudio): todos, inclusive os da equipe; o arquivo sai do storage depois do commit.
  def limpar_conversas
    mensagens = Message.where(conversation_id: conversa_ids)
    Attachment.where(message_id: mensagens.select(:id)).find_each(&:destroy!)
    mensagens.update_all(content_attributes: {})
    Conversation.where(id: conversa_ids).update_all(additional_attributes: {})
    @contact.contact_inboxes.find_each { |ci| ci.update_columns(source_id: "anonimizado-#{ci.id}") }
    limpar_registros_da_ia
  end

  def limpar_registros_da_ia
    Captain::ToolRun.where(conversation_id: conversa_ids).or(Captain::ToolRun.where(lead_id: lead_ids)).update_all(params: {}, resultado: nil)
    AgenteExecucao.where(conversation_id: conversa_ids).or(AgenteExecucao.where(lead_id: lead_ids))
                  .update_all(pedido: '[anonimizado]', resumo: nil, acoes: [])
    mascarar_faqs if ChatwootApp.enterprise? # FAQ é modelo do enterprise
  end

  def mascarar_faqs
    Captain::AssistantResponse.where(documentable_type: 'Conversation', documentable_id: conversa_ids).find_each do |faq|
      faq.update_columns(question: @mask.call(faq.question), answer: @mask.call(faq.answer))
    end
  end

  # Execução de fluxo guarda o gatilho (mensagem, nome) no contexto; a que ainda ia rodar é cancelada.
  def limpar_execucoes
    { 'Lead' => lead_ids, 'Conversation' => conversa_ids,
      'LeadTask' => LeadTask.where(lead_id: lead_ids).select(:id), 'Reuniao' => Reuniao.where(lead_id: lead_ids).select(:id) }.each do |tipo, ids|
      execucoes = FluxoExecucao.where(alvo_type: tipo, alvo_id: ids)
      execucoes.where(status: ATIVAS).update_all(status: 'cancelada', retomar_em: nil)
      execucoes.update_all(contexto: {}, trilha: [], erro: nil)
    end
  end

  def lead_ids = @leads.map(&:id)

  def conversa_ids = @contact.conversations.select(:id)
end
# rubocop:enable Rails/SkipsModelValidations
