# Consequências fixas de uma saída do roteiro (spec 2026-10-13 §3.4) — configuradas pelo admin no passo; a IA não
# decide. Por modo da conversa (decisões 13/10): etiqueta e "passar para a equipe" valem direto em qualquer modo;
# etapa (só aberta) e Perdido só direto em piloto total — nos outros modos, e sem conversa, viram sugestão no Cockpit.
# Perdido de verdade = etiqueta desqualificado-ia + IA calada (a conversa fica com o robô). Histórico: LeadActivity 'roteiro'.
module Ramon::Roteiro::Efeitos
  ETIQUETA_DESQUALIFICADO = 'desqualificado-ia'.freeze
  MOTIVO_PERDA_PADRAO = 'Sem viabilidade'.freeze
  MODO_ANTES = 'copiloto_modo_antes_roteiro'.freeze
  ENCERRA = %w[desqualificar humano concluir].freeze

  module_function

  def aplicar(lead, passo, saida)
    efeitos = saida['efeitos'] || {}
    etiquetar(lead, efeitos['etiqueta'])
    mover(lead, efeitos['etapa'], passo)
    desqualificar(lead, passo, saida) if saida['acao'] == 'desqualificar'
    humano(lead, saida['motivo']) if saida['acao'] == 'humano'
    anotar(lead, "#{passo.titulo} → #{resumo(saida)}") if ENCERRA.include?(saida['acao']) || efeitos.values.any?(&:present?)
  end

  # Etapa e Perdido direto no piloto total e nos modos "sozinha até…" (F3), pelo modo efetivo da conversa
  # (atributo → caixa → env). Lead sem conversa nunca é direto.
  def direto?(lead)
    lead.conversation.present? && Ramon::CopilotoModo.direto?(Ramon::CopilotoModo.of(lead.conversation))
  end

  # Label do Chatwoot é minúscula (Label#title.downcase).
  def etiquetar(lead, etiqueta)
    return if etiqueta.blank? || lead.conversation.nil?

    lead.conversation.reload.add_labels([etiqueta.to_s.downcase])
  end

  # Só etapa aberta: ganho nunca; perdido só pela saída desqualificar. Nunca para trás (como registrar_reuniao!).
  def mover(lead, nome, passo)
    return if nome.blank?

    etapa = lead.account.lead_stages.find_by(name: nome, is_won: false, is_lost: false)
    return anotar(lead, "etapa '#{nome}' nao existe no funil") if etapa.nil?
    return if lead.lead_stage.position >= etapa.position
    return lead.update!(lead_stage: etapa) if direto?(lead)

    sugerir(lead, 'move_stage', 'etapa_sugerida' => etapa.name, 'justificativa' => "roteiro da IA: #{passo.titulo}")
  end

  def desqualificar(lead, passo, saida)
    return if lead.won_at || lead.lost_at

    motivo_perda = saida['motivo_perda'].presence || MOTIVO_PERDA_PADRAO
    return perder(lead, motivo_perda) if direto?(lead)

    sugerir(lead, 'acao', 'acao' => 'perdido', 'lost_reason' => motivo_perda,
                          'texto' => "Marcar como perdido (#{motivo_perda}) - roteiro: #{passo.titulo}, #{saida['motivo']}")
  end

  def perder(lead, motivo_perda)
    perdido = lead.account.lead_stages.find_by(is_lost: true)
    lead.update!(lead_stage: perdido, lost_reason: motivo_perda) if perdido
    calar(lead)
  end

  # A mensagem de encerramento desta resposta ainda sai: o ResponseBuilderJob guarda o modo do início da resposta.
  # Também chamada ao aprovar o Perdido sugerido pelo roteiro (CopilotSuggestion#marcar_perdido).
  def calar(lead)
    etiquetar(lead, ETIQUETA_DESQUALIFICADO)
    modo(lead, 'manual')
  end

  # Roteiro reaberto (Ramon::Roteiro.reabrir): devolve o modo de antes e tira a etiqueta de desqualificado.
  def reabrir(lead)
    restaurar(lead.conversation) if lead.conversation
    anotar(lead, 'roteiro reaberto')
  end

  def restaurar(conversa)
    conversa.reload
    attrs = conversa.custom_attributes || {}
    conversa.update!(custom_attributes: attrs.except(MODO_ANTES).merge('copiloto_modo' => attrs[MODO_ANTES])) if attrs.key?(MODO_ANTES)
    return unless conversa.label_list.include?(ETIQUETA_DESQUALIFICADO)

    conversa.update_labels(conversa.label_list - [ETIQUETA_DESQUALIFICADO])
  end

  # Como as tools de escrita: pendente igual (mesmo caso, mesmo tipo/ação) não vira duas.
  def sugerir(lead, kind, payload)
    pendentes = lead.account.copilot_suggestions.pending.where(lead_id: lead.id, kind: kind)
    return if pendentes.any? { |s| s.payload['acao'] == payload['acao'] }

    lead.account.copilot_suggestions.create!(
      lead: lead, kind: kind, status: 'pending', run_at: Time.current,
      payload: payload.merge('origem' => 'roteiro', 'lead_name' => lead.name, 'stage_name' => lead.lead_stage&.name)
    )
  end

  # Mesmo caminho da tool handoff (bot_handoff!); sino ao closer/SDR do lead, sem eles aos gestores.
  def humano(lead, motivo)
    conversa = lead.conversation
    conversa.bot_handoff! if conversa&.pending?
    modo(lead, 'rascunho')
    ids = [lead.closer_id || lead.sdr_id].compact.presence || Ramon::Papeis.gestor_ids(lead.account)
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso', user_ids: ids,
                                       meta: { 'label' => "IA passou #{lead.name} para a equipe: #{motivo}".truncate(200) }).perform
    Ramon::NtfyPushJob.perform_later(lead.id, title: "IA passou para a equipe: #{lead.name}", body: motivo.to_s.truncate(200))
  end

  # Guarda o modo de antes para o reabrir devolver (decisão 13/10); o 1º modo vale até o reabrir.
  def modo(lead, valor)
    conversa = lead.conversation
    return if conversa.nil?

    attrs = conversa.custom_attributes || {}
    antes = attrs.key?(MODO_ANTES) ? {} : { MODO_ANTES => attrs['copiloto_modo'] }
    conversa.update!(custom_attributes: attrs.merge(antes).merge('copiloto_modo' => valor))
  end

  def resumo(saida)
    case saida['acao']
    when 'desqualificar' then "desqualificado: #{saida['motivo']}"
    when 'humano' then "passou para a equipe: #{saida['motivo']}"
    when 'concluir' then 'qualificado'
    else saida['acao']
    end
  end

  def anotar(lead, texto)
    lead.lead_activities.create!(account: lead.account, kind: 'roteiro', to_value: texto.truncate(250))
  end
end
