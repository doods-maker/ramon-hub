# Consequências fixas de uma saída do roteiro (spec 2026-10-13 §3.4) — configuradas pelo admin no passo; a IA não
# decide. Por modo da conversa (decisões 13/10): etiqueta e "passar para a equipe" valem direto em qualquer modo;
# etapa (só aberta) e Perdido só direto nos modos diretos (piloto total e "sozinha até…") — nos outros, e sem
# conversa, viram sugestão no Cockpit. Perdido de verdade = etiqueta desqualificado-ia + IA calada (a conversa fica com
# o robô). Histórico: LeadActivity 'roteiro'. Modo da conversa: Ramon::CopilotoModo; avisos: Ramon::AvisoDaIa.
module Ramon::Roteiro::Efeitos
  ETIQUETA_DESQUALIFICADO = 'desqualificado-ia'.freeze
  MOTIVO_PERDA_PADRAO = 'Sem viabilidade'.freeze

  module_function

  def aplicar(lead, passo, saida)
    efeitos = saida['efeitos'] || {}
    etiquetar(lead, efeitos['etiqueta'])
    mover(lead, efeitos['etapa'], passo)
    desqualificar(lead, passo, saida) if saida['acao'] == 'desqualificar'
    humano(lead, saida) if saida['acao'] == 'humano'
    anotar(lead, "#{passo.titulo} → #{resumo(saida)}") if anota?(saida, efeitos)
    Ramon::CopilotoLimite.verificar(lead)
  end

  def anota?(saida, efeitos)
    Ramon::Roteiro::DESFECHO_DA_ACAO.key?(saida['acao']) || efeitos.values.any?(&:present?)
  end

  # Etapa e Perdido direto no piloto total e nos modos "sozinha até…" (F3), pelo modo efetivo da conversa do lead.
  def direto?(lead)
    Ramon::CopilotoModo.direto?(lead.copiloto_modo)
  end

  # O que a desqualificação faz agora — predicado único (o Registro marca aguarda_equipe com ele):
  # :nada (lead ganho ou perdido), :perder (modo direto) ou :sugerir (o Perdido vira sugestão no Cockpit).
  def desqualificacao(lead)
    return :nada if lead.won_at || lead.lost_at

    direto?(lead) ? :perder : :sugerir
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
    motivo_perda = saida['motivo_perda'].presence || MOTIVO_PERDA_PADRAO
    case desqualificacao(lead)
    when :perder then perder(lead, motivo_perda)
    when :sugerir
      sugerir(lead, 'acao', 'acao' => 'perdido', 'lost_reason' => motivo_perda,
                            'texto' => "Marcar como perdido (#{motivo_perda}) - roteiro: #{passo.titulo}, #{saida['motivo']}")
    end
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
    Ramon::CopilotoModo.trocar(lead.conversation, 'manual') if lead.conversation
  end

  # Roteiro reaberto (Ramon::Roteiro.reabrir): devolve o modo de antes e tira a etiqueta de desqualificado.
  def reabrir(lead)
    conversa = lead.conversation
    if conversa
      Ramon::CopilotoModo.restaurar(conversa)
      tirar_etiqueta(conversa)
    end
    anotar(lead, 'roteiro reaberto')
  end

  def tirar_etiqueta(conversa)
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

  # Mesmo caminho da tool handoff (bot_handoff!). Roteiro sem saída (configuração quebrada, spec §5) avisa também os
  # administradores, além do responsável.
  def humano(lead, saida)
    conversa = lead.conversation
    conversa.bot_handoff! if conversa&.pending?
    Ramon::CopilotoModo.trocar(conversa, 'rascunho') if conversa
    motivo = saida['motivo']
    Ramon::AvisoDaIa.avisar(lead, "IA passou #{lead.name} para a equipe: #{motivo}", "IA passou para a equipe: #{lead.name}",
                            motivo, admins: saida['id'] == Ramon::Roteiro::SEM_SAIDA)
  end

  def resumo(saida)
    case Ramon::Roteiro::DESFECHO_DA_ACAO[saida['acao']]
    when Ramon::Roteiro::DESQUALIFICADO then "desqualificado: #{saida['motivo']}"
    when Ramon::Roteiro::HUMANO then "passou para a equipe: #{saida['motivo']}"
    when Ramon::Roteiro::QUALIFICADO then 'qualificado'
    else saida['acao']
    end
  end

  def anotar(lead, texto)
    lead.lead_activities.create!(account: lead.account, kind: 'roteiro', to_value: texto.truncate(250))
  end
end
