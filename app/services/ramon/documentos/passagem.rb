# Checklist completo na etapa Documentos → Jurídico (spec Etapa Documentos §8; só com a chave ligada). Chamado pelo
# PassagemJob: do gancho do lead (docs_completos_em preenchido em Documentos) ou da entrada em Documentos já completo.
# 1. Sob o lock do lead, se ele ainda está em Documentos e completo: o encerramento aprovado sai pelo Envio (na janela de 24 h,
#    mesmo com a conversa já com uma pessoa: decisão do Eduardo, 07/11; respeita Pausa e rascunho do Perfil da IA) e o lead vai a Jurídico.
# 2. A conversa sai da IA (bot_handoff!: aberta, com quem já a tinha; em Jurídico o Perfil da IA é :fechado).
# 3. A ANÁLISE DO CASO no ADVBOX (Ramon::AdvboxDocsTaskService#analise_do_caso), uma por caso. Sem o processo do Ganho, os
#    administradores são avisados e a tarefa sai quando o caso aparecer (retomar, no fim do AdvboxClosingService).
# Idempotente: rodar de novo (retry do job com o ADVBOX fora do ar) só tenta a tarefa. A pasta "— COMPLETO" é do Drive
# (DriveExportService#concluir), que já roda a cada atualização dos documentos.
module Ramon::Documentos::Passagem
  CONFIG = Ramon::Documentos::Cobranca::CONFIG
  PROBLEMAS = {
    sem_caso: 'o Ganho não conseguiu abrir o caso no ADVBOX (veja o erro no lead). Ela sai sozinha quando o caso for aberto',
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
    juridico = Ramon::EtapaDeGanho.juridico(lead.account)
    andou = juridico && lead.with_lock do
      next false unless Ramon::EtapaDeGanho.conduzida?(lead.lead_stage) && lead.docs_completos_em.present?

      encerrar(lead)
      lead.update!(lead_stage: juridico)
    end
    return unless andou

    lead.conversation.bot_handoff! if lead.conversation&.pending?
    registrar(lead, 'Checklist completo: o lead foi para o Jurídico e a conversa saiu da IA')
  end

  # Sai mesmo com a conversa já com uma pessoa (decisão do Eduardo, 07/11); Pausa e rascunho do Perfil da IA continuam valendo.
  def encerrar(lead)
    conversa = lead.conversation
    unless conversa && Ramon::PerfilIa.de(conversa).logistica_sai_agora?
      return registrar(lead, 'Passagem: o encerramento não saiu (IA em Pausa ou em rascunho agora)')
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
    # Sem caso e sem erro: o ADVBOX do Ganho ainda não rodou (job na fila); o retomar, no fim dele, cria a tarefa.
    return if resultado == :sem_caso && lead.custom_attributes&.dig('advbox', 'erro').blank?

    Ramon::AvisoDaIa.avisar(lead, "ANÁLISE DO CASO de #{lead.name} não foi criada no ADVBOX: #{PROBLEMAS.fetch(resultado)}",
                            "Jurídico: ANÁLISE DO CASO pendente (#{Ramon::NtfyPushJob.rotulo(lead)})", 'Veja o aviso no sino', user_ids: [])
  end

  # Gancho do lead (after_commit de toda gravação do custom_attributes): documento que saiu de "recebido" num lead do Jurídico
  # → o aviso, num job (quem desmarcou não pode tomar erro). mudanca: o saved_change do custom_attributes (antes, depois).
  def desmarcou(lead, mudanca, user)
    return unless Ramon::EtapaDeGanho.documentos_ligado? && no_juridico?(lead)

    ids = saidos_de_recebido(mudanca)
    Ramon::Documentos::DesmarcadoJob.perform_later(lead.id, ids, user&.id) if ids.any?
  end

  def saidos_de_recebido(mudanca)
    antes, depois = mudanca.map { |attrs| attrs.to_h['doc_status'].to_h }
    antes.select { |id, status| status == 'recebido' && depois[id] != 'recebido' }.keys
  end

  # Spec §8: o lead não volta sozinho, quem desmarcou decide; a equipe sempre fica sabendo. Sino ao SDR (sem SDR, o closer) e ao
  # responsável da ANÁLISE DO CASO (o usuário do hub com o e-mail do ADVBOX dele); sem nenhum dos dois, os administradores.
  # Nota privada e histórico com quem desmarcou; push só com a tese. A tarefa no ADVBOX não é tocada.
  def avisar_desmarcado(lead, item_ids, user)
    return unless no_juridico?(lead)

    texto = "#{desmarcados(lead, item_ids)}, que já está no Jurídico: decidir se volta para Documentos"
    Ramon::AvisoDaIa.avisar(lead, texto, "Jurídico: documento desmarcado (#{Ramon::NtfyPushJob.rotulo(lead)})",
                            'Decidir se volta para Documentos', user_ids: [lead.sdr_id || lead.closer_id, responsavel_da_analise(lead)].compact.uniq)
    nota = "#{texto}. Desmarcado por #{user&.name || 'automação'}; a tarefa no ADVBOX não foi mexida."
    Messages::MessageBuilder.new(nil, lead.conversation, { content: nota, private: true }).perform if lead.conversation
    registrar(lead, nota)
  end

  def desmarcados(lead, item_ids)
    titulos = ThesisItem.where(id: item_ids, thesis_id: lead.thesis_id).order(:position).pluck(:title)
    verbo = titulos.one? ? 'foi desmarcado' : 'foram desmarcados'
    "#{titulos.to_sentence(two_words_connector: ' e ', last_word_connector: ' e ').presence || 'Um documento'} #{verbo} de #{lead.name}"
  end

  # ADVBOX fora do ar (o e-mail vem das configurações dele, em cache de 24 h): o aviso sai sem ele.
  def responsavel_da_analise(lead)
    Ramon::AgendaHojeService.new(lead.account).usuario_do_hub(Ramon::AdvboxClosingService::USERS_ID)&.id
  rescue StandardError => e
    Rails.logger.warn("[Ramon::Documentos::Passagem] responsável da ANÁLISE DO CASO não achado: #{e.class}")
    nil
  end

  def registrar_tarefa(lead, resultado)
    registrar(lead, 'Jurídico: tarefa ANÁLISE DO CASO criada no ADVBOX') if resultado == :criada
  end

  def no_juridico?(lead) = Ramon::EtapaDeGanho.juridico?(lead.lead_stage)

  def registrar(lead, texto) = Ramon::Documentos::Entrada.registrar(lead, texto)
end
