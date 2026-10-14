# Modos "sozinha até…" (spec roteiro §3.7, F3): a IA envia direto até o limite do modo; ao atingir, a conversa volta
# para rascunho, fica o carimbo copiloto_limite (métricas da F4) e o responsável recebe sino + push.
# SEM handoff: a resposta do turno que atingiu o limite ainda sai (o ResponseBuilderJob guarda o modo do início e só
# publica com a conversa pendente) — é assim que o link do contrato chega ao lead.
# Níveis em ordem: chegar a um mais adiante também encerra os de antes. Quem chama: Lead (etapa ou ZapSign mudou),
# o roteiro (fim de Efeitos.aplicar) e o contrato automático que não saiu (Ramon::ContratoAutomatico).
module Ramon::CopilotoLimite
  QUALIFICACAO = 'qualificacao'.freeze
  REUNIAO = 'reuniao'.freeze
  CONTRATO = 'contrato'.freeze
  NIVEIS = [QUALIFICACAO, REUNIAO, CONTRATO].freeze
  # O contrato automático não saiu (falta dado ou o ZapSign falhou): encerra o modo como um limite, mas conta à parte
  # (bi_roteiro, card de limites) — 'contrato' fica só para o contrato que de fato saiu.
  CONTRATO_FALHOU = 'contrato_falhou'.freeze
  NOMES = { QUALIFICACAO => 'lead qualificado', REUNIAO => 'reunião marcada', CONTRATO => 'contrato enviado',
            CONTRATO_FALHOU => 'contrato não saiu na hora' }.freeze

  module_function

  # @return [String, nil] o limite encerrado agora
  def verificar(lead)
    limite = Ramon::CopilotoModo::LIMITES[lead.copiloto_modo]
    encerrar(lead, limite) if limite && atingido?(limite, lead)
  end

  # Idempotente: fora de um modo "até…" (já encerrado, ou nunca esteve) não faz nada.
  def encerrar(lead, limite, motivo = nil)
    modo = lead.copiloto_modo
    return unless lead.conversation && Ramon::CopilotoModo::LIMITES.key?(modo)

    conversa = lead.conversation
    carimbo = { 'limite' => limite, 'modo' => modo, 'motivo' => motivo, 'em' => Time.zone.now.iso8601 }.compact
    conversa.update!(custom_attributes: (conversa.custom_attributes || {}).merge('copiloto_modo' => 'rascunho',
                                                                                 'copiloto_limite' => carimbo))
    avisar(lead, limite, motivo)
    limite
  end

  # Reabrir o roteiro desfaz o limite que o desfecho causou: volta o modo de antes do carimbo e apaga o carimbo. Só com
  # a conversa ainda no rascunho em que o limite a deixou — o modo que um humano escolheu depois (o carimbo fica) vale.
  def desfazer(conversa, limite)
    attrs = conversa.reload.custom_attributes || {}
    carimbo = attrs['copiloto_limite']
    return unless carimbo.is_a?(Hash) && carimbo['limite'] == limite && Ramon::CopilotoModo::MODOS.include?(carimbo['modo'])
    return unless attrs['copiloto_modo'] == 'rascunho'

    conversa.update!(custom_attributes: attrs.except('copiloto_limite').merge('copiloto_modo' => carimbo['modo']))
  end

  def atingido?(limite, lead)
    alcancado = nivel(lead)
    !alcancado.nil? && NIVEIS.index(alcancado) >= NIVEIS.index(limite)
  end

  # Qualificação = só o desfecho qualificado do roteiro (desqualificado/equipe já encerram pelos efeitos da F1).
  def nivel(lead)
    return CONTRATO if lead.won_at.present? || lead.contrato_enviado?
    return REUNIAO if reuniao?(lead)

    QUALIFICACAO if lead.desfecho_roteiro == Ramon::Roteiro::QUALIFICADO
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
    Ramon::AvisoDaIa.avisar(lead, texto, "IA chegou ao limite: #{lead.name}", motivo ? "#{NOMES[limite]}: #{motivo}" : NOMES[limite])
  end
end
