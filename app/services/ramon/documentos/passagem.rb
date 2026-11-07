# Checklist completo na etapa Documentos → Jurídico (spec Etapa Documentos §8; só com a chave ligada). Chamado pelo
# PassagemJob: do gancho do lead (docs_completos_em preenchido em Documentos) ou da entrada em Documentos já completo.
# 1. Sob o lock do lead, se ele ainda está em Documentos e completo: o encerramento aprovado sai pelo Envio (só com a conversa
#    com a IA e na janela de 24 h; antes de andar, enquanto o assistente da conversa é o de Documentos) e o lead vai a Jurídico.
# 2. A conversa sai da IA (bot_handoff!: aberta, com quem já a tinha; em Jurídico o Perfil da IA é :fechado).
# 3. A ANÁLISE DO CASO no ADVBOX (Ramon::AdvboxDocsTaskService#analise_do_caso), uma por caso. Sem o processo do Ganho, os
#    administradores são avisados e a tarefa sai quando o caso aparecer (retomar, no fim do AdvboxClosingService).
# Idempotente: rodar de novo (retry do job com o ADVBOX fora do ar) só tenta a tarefa. A pasta "— COMPLETO" é do Drive
# (DriveExportService#concluir), que já roda a cada atualização dos documentos.
module Ramon::Documentos::Passagem
  CONFIG = Ramon::Documentos::Cobranca::CONFIG
  PROBLEMAS = {
    sem_caso: 'o caso não existe no ADVBOX (o Ganho não abriu; veja o erro no lead). Ela sai sozinha quando o caso for aberto',
    recusada: 'o ADVBOX recusou. Criar à mão',
    sem_token: 'o hub está sem o token do ADVBOX. Criar à mão'
  }.freeze

  module_function

  def call(lead)
    return unless Ramon::EtapaDeGanho.documentos_ligado?

    passar(lead)
    analise(lead) if no_juridico?(lead.reload)
  end

  # O caso apareceu no ADVBOX depois da passagem (AdvboxClosingService): a tarefa que ficou para trás, sem novo aviso. Só com o
  # checklist completo: quem foi arrastado à mão para o Jurídico, incompleto, não ganha a tarefa.
  def retomar(lead)
    return unless Ramon::EtapaDeGanho.documentos_ligado? && no_juridico?(lead) && lead.docs_completos_em.present?

    registrar_tarefa(lead, Ramon::AdvboxDocsTaskService.new(lead).analise_do_caso)
  end

  def passar(lead)
    juridico = lead.account.lead_stages.find_by(label: Ramon::EtapaDeGanho::JURIDICO, is_won: true)
    andou = juridico && lead.with_lock do
      next false unless Ramon::EtapaDeGanho.conduzida?(lead.lead_stage) && lead.docs_completos_em.present?

      encerrar(lead)
      lead.update!(lead_stage: juridico)
    end
    return unless andou

    lead.conversation.bot_handoff! if lead.conversation&.pending?
    registrar(lead, 'Checklist completo: o lead foi para o Jurídico e a conversa saiu da IA')
  end

  def encerrar(lead)
    conversa = lead.conversation
    unless conversa && Ramon::Documentos::PassoAPasso.sai_agora?(conversa)
      return registrar(lead, 'Passagem: o encerramento não saiu (a conversa não está com a IA, ou a IA está em rascunho agora)')
    end

    case Ramon::Documentos::Envio.mandar(lead, :encerramento)
    when :texto
      registrar(lead, 'Passagem: enviou o encerramento (texto livre, na janela de 24 h)')
      Ramon::LlmUso.registrar_whatsapp(lead, model: 'texto livre', custo_usd: CONFIG['custo_usd_por_mensagem'])
    when :desligado then registrar(lead, 'Passagem: o encerramento está desligado na configuração (texto vazio): não saiu')
    else registrar(lead, 'Passagem: o encerramento não saiu (janela de 24 h fechada)')
    end
  end

  def analise(lead)
    resultado = Ramon::AdvboxDocsTaskService.new(lead).analise_do_caso
    registrar_tarefa(lead, resultado)
    return unless PROBLEMAS.key?(resultado)

    Ramon::AvisoDaIa.avisar(lead, "ANÁLISE DO CASO de #{lead.name} não foi criada no ADVBOX: #{PROBLEMAS.fetch(resultado)}",
                            "Jurídico: ANÁLISE DO CASO pendente (#{Ramon::NtfyPushJob.rotulo(lead)})", 'Veja o aviso no sino', user_ids: [])
  end

  # Desmarcaram um documento de quem já está no Jurídico (o carimbo docs_completos_em sumiu; gancho do lead): o lead não volta
  # sozinho, quem desmarcou decide. Sino ao SDR (sem SDR, o closer) e aos administradores (o responsável da ANÁLISE DO CASO é o
  # Eduardo), nota privada e histórico com quem desmarcou; push só com a tese. A tarefa no ADVBOX não é tocada.
  # mudanca: o saved_change do custom_attributes (antes, depois); nil quando o que mudou foi a tese.
  def desmarcado(lead, mudanca, user)
    return unless Ramon::EtapaDeGanho.documentos_ligado? && no_juridico?(lead)

    texto = "#{desmarcados(lead, mudanca)}, que já está no Jurídico: decidir se volta para Documentos"
    Ramon::AvisoDaIa.avisar(lead, texto, "Jurídico: documento desmarcado (#{Ramon::NtfyPushJob.rotulo(lead)})",
                            'Decidir se volta para Documentos', user_ids: [lead.sdr_id || lead.closer_id].compact, admins: true)
    nota = "#{texto}. Desmarcado por #{user&.name || 'automação'}; a tarefa no ADVBOX não foi mexida."
    Messages::MessageBuilder.new(nil, lead.conversation, { content: nota, private: true }).perform if lead.conversation
    registrar(lead, nota)
  end

  def desmarcados(lead, mudanca)
    antes, depois = Array(mudanca).map { |attrs| attrs.to_h.fetch('doc_status', {}) }
    ids = antes.to_h.select { |id, status| status == 'recebido' && depois.to_h[id] != 'recebido' }.keys
    titulos = ThesisItem.where(id: ids, thesis_id: lead.thesis_id).order(:position).pluck(:title)
    return "O checklist de #{lead.name} ficou incompleto" if titulos.empty?

    verbo = titulos.one? ? 'foi desmarcado' : 'foram desmarcados'
    "#{titulos.to_sentence(two_words_connector: ' e ', last_word_connector: ' e ')} #{verbo} de #{lead.name}"
  end

  def registrar_tarefa(lead, resultado)
    registrar(lead, 'Jurídico: tarefa ANÁLISE DO CASO criada no ADVBOX') if resultado == :criada
  end

  def no_juridico?(lead) = lead.lead_stage&.label == Ramon::EtapaDeGanho::JURIDICO

  def registrar(lead, texto) = Ramon::Documentos::Entrada.registrar(lead, texto)
end
