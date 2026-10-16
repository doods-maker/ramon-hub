# Regras fixas do funil automático (sem IA): cada uma passa pela chave da peça em Ramon::FunilAutomatico.
# Conferência e update sob lead.with_lock (relê o lead): um lead velho em memória nunca regrava won_at nem passa por
# cima de um Ganho/Perdido que outro processo acabou de gravar.
class Ramon::FunilRegras
  # Contrato criado no ZapSign → Negociação (só avança, nunca volta).
  def self.contrato_criado(lead)
    seguro(lead) { mover_para_frente(lead, 'fase-negociacao', peca: 'zapsign_negociacao', motivo: 'contrato enviado pelo ZapSign') }
  end

  # Contrato assinado → Ganho, até saindo de Perdido (assinatura vale mais que tudo). O value estimado congela sozinho.
  def self.contrato_assinado(lead)
    seguro(lead) { marcar_ganho(lead) }
  end

  def self.marcar_ganho(lead)
    ganho = lead.account.lead_stages.find_by(is_won: true)
    return if ganho.nil?

    lead.with_lock do
      next if lead.lead_stage.is_won

      # saindo de Perdido, o desfazer guarda o motivo: voltar a Perdido sem ele dá 422
      desfazer = { 'etapa_id' => lead.lead_stage_id, 'lost_reason' => lead.lost_reason }.compact
      Ramon::FunilAutomatico.executar(lead, peca: 'zapsign_ganho', acao: 'marcar_ganho', motivo: 'contrato assinado no ZapSign',
                                            alvo: ganho.name, desfazer: desfazer) do
        lead.update!(lead_stage: ganho)
      end
    end
  end

  # Leva o lead à etapa `label` só se ela estiver à frente da atual e o lead ainda estiver aberto.
  def self.mover_para_frente(lead, label, peca:, motivo:)
    etapa = lead.account.lead_stages.find_by(label: label)
    return if etapa.nil?

    lead.with_lock do
      atual = lead.lead_stage
      next if atual.is_won || atual.is_lost || atual.position >= etapa.position

      Ramon::FunilAutomatico.executar(lead, peca: peca, acao: 'mover_etapa', motivo: motivo, alvo: etapa.name,
                                            desfazer: { 'etapa_id' => atual.id }) do
        lead.update!(lead_stage: etapa)
      end
    end
  end

  # Efeito opcional atrás de chave nunca derruba a ação principal (contrato já criado/assinado e fluxos).
  def self.seguro(lead)
    yield
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: lead.account).capture_exception
    Rails.logger.error("FunilRegras falhou no lead #{lead.id}: #{e.class}: #{e.message}")
    nil
  end
  private_class_method :marcar_ganho, :seguro
end
