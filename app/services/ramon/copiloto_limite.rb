# Modos "sozinha até…" (spec roteiro §3.7, F3): a IA envia direto até o limite do modo; ao atingir, a conversa volta
# para rascunho, fica o carimbo copiloto_limite (métricas da F4) e o responsável recebe sino + push.
# SEM handoff: a resposta do turno que atingiu o limite ainda sai (o ResponseBuilderJob guarda o modo do início e só
# publica com a conversa pendente) — é assim que o link do contrato chega ao lead.
# Níveis em ordem: chegar a um mais adiante também encerra os de antes. Quem chama: Lead (etapa ou ZapSign mudou),
# o roteiro (fim de Efeitos.aplicar) e o contrato automático que não saiu (Ramon::ContratoAutomatico).
module Ramon::CopilotoLimite
  NIVEIS = %w[qualificacao reuniao contrato].freeze
  NOMES = { 'qualificacao' => 'lead qualificado', 'reuniao' => 'reunião marcada', 'contrato' => 'contrato enviado' }.freeze

  module_function

  # @return [String, nil] o limite encerrado agora
  def verificar(lead)
    return if lead.conversation.nil?

    limite = Ramon::CopilotoModo::LIMITES[Ramon::CopilotoModo.of(lead.conversation)]
    encerrar(lead, limite) if limite && atingido?(limite, lead)
  end

  # Idempotente: fora de um modo "até…" (já encerrado, ou nunca esteve) não faz nada.
  def encerrar(lead, limite, motivo = nil)
    conversa = lead.conversation
    modo = conversa && Ramon::CopilotoModo.of(conversa)
    return unless Ramon::CopilotoModo::LIMITES.key?(modo)

    carimbo = { 'limite' => limite, 'modo' => modo, 'motivo' => motivo, 'em' => Time.zone.now.iso8601 }.compact
    conversa.update!(custom_attributes: (conversa.custom_attributes || {}).merge('copiloto_modo' => 'rascunho',
                                                                                 'copiloto_limite' => carimbo))
    avisar(lead, limite, motivo)
    limite
  end

  def atingido?(limite, lead)
    alcancado = nivel(lead)
    !alcancado.nil? && NIVEIS.index(alcancado) >= NIVEIS.index(limite)
  end

  # Qualificação = só o desfecho qualificado do roteiro (desqualificado/equipe já encerram pelos efeitos da F1).
  def nivel(lead)
    return 'contrato' if lead.custom_attributes&.dig('zapsign', 'sign_url').present?
    return 'reuniao' if reuniao?(lead)

    'qualificacao' if lead.custom_attributes&.dig('roteiro', 'desfecho') == 'qualificado'
  end

  # Link do ZapSign mudou no lead (callback do Lead; a mudança só do roteiro NÃO entra, ver Lead).
  def contrato_mudou?(lead)
    lead.saved_change_to_custom_attributes? &&
      lead.custom_attributes_before_last_save.to_h['zapsign'] != lead.custom_attributes.to_h['zapsign']
  end

  # Reunião agendada ou qualquer etapa depois dela (ganho incluso); Perdido não conta.
  def reuniao?(lead)
    etapa = lead.lead_stage
    marco = lead.account.lead_stages.find_by(label: Ramon::ReuniaoAgendamento::STAGE_LABEL)
    etapa.present? && marco.present? && !etapa.is_lost && etapa.position >= marco.position
  end

  def avisar(lead, limite, motivo)
    texto = "IA chegou ao limite (#{NOMES[limite]}) com #{lead.name}#{": #{motivo}" if motivo} - conversa em rascunho"
    Ramon::Roteiro::Efeitos.avisar(lead, texto, "IA chegou ao limite: #{lead.name}", motivo || NOMES[limite])
  end
end
