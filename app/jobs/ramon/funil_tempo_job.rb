# Regras de tempo do funil (1x/dia): Última chance parada → Perdido 'Sumiu / não respondeu'; Negociação parada → Última chance.
# Perdido primeiro, para o lead não andar duas etapas no mesmo dia. Cada regra passa pela chave da sua peça.
# "Parado" = na etapa além do prazo E sem mensagem do cliente nesse prazo (ruling 16/10: quem conversa todo dia não "sumiu").
class Ramon::FunilTempoJob < ApplicationJob
  queue_as :low

  MOTIVO_PERDA = 'Sumiu / não respondeu'.freeze

  def perform
    Account.find_each do |account|
      perder_sumidos(account) if Ramon::FunilAutomatico.modo(account, 'tempo_perdido') != 'off'
      avancar_negociacao(account) if Ramon::FunilAutomatico.modo(account, 'tempo_ultima_chance') != 'off'
    end
  end

  private

  def perder_sumidos(account)
    perdido = account.lead_stages.find_by(is_lost: true)
    return if perdido.nil?

    cada_parado(account, 'fase-ultima-chance') do |lead|
      Ramon::FunilAutomatico.executar(lead, peca: 'tempo_perdido', acao: 'mover_etapa', motivo: MOTIVO_PERDA, alvo: perdido.name,
                                            desfazer: { 'etapa_id' => lead.lead_stage_id }) do
        lead.update!(lead_stage: perdido, lost_reason: MOTIVO_PERDA)
      end
    end
  end

  def avancar_negociacao(account)
    cada_parado(account, 'fase-negociacao') do |lead|
      Ramon::FunilRegras.mover_para_frente(lead, 'fase-ultima-chance', peca: 'tempo_ultima_chance',
                                                                       motivo: 'Negociação parada sem resposta')
    end
  end

  # Por lead, sob lock (relê o lead): a conferência vale para o estado atual, nunca para o da consulta. Um lead com
  # problema não para os outros nem a outra regra.
  def cada_parado(account, label)
    etapa = account.lead_stages.find_by(label: label)
    return if etapa.nil?

    Ramon::Cadencia.parados(account.leads.where(lead_stage: etapa)).find_each do |lead|
      lead.with_lock { yield lead if parado?(lead, etapa) }
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: account).capture_exception
      Rails.logger.error("FunilTempoJob: lead #{lead.id} falhou (#{e.class}: #{e.message})")
    end
  end

  # Sem conversa = só o tempo na etapa.
  def parado?(lead, etapa)
    return false unless lead.lead_stage_id == etapa.id && Ramon::Cadencia.parado?(lead)

    ultima = ultima_do_cliente(lead)
    ultima.nil? || ultima < etapa.stalled_after_days.days.ago
  end

  def ultima_do_cliente(lead)
    lead.conversation&.messages&.incoming&.where(private: false)&.maximum(:created_at)
  end
end
