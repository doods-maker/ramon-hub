# Regras de tempo do funil (1x/dia): Última chance parada → Perdido 'Sumiu / não respondeu'; Negociação parada → Última chance.
# Perdido primeiro, para o lead não andar duas etapas no mesmo dia. Cada regra passa pela chave da sua peça.
class Ramon::FunilTempoJob < ApplicationJob
  queue_as :low

  MOTIVO_PERDA = 'Sumiu / não respondeu'.freeze

  def perform
    Account.find_each do |account|
      processar(account)
    rescue StandardError => e
      # uma conta com problema (etapa faltando, etc.) não para as outras
      Rails.logger.error("FunilTempoJob: conta #{account.id} falhou (#{e.class}: #{e.message})")
    end
  end

  private

  def processar(account)
    perder_sumidos(account) if Ramon::FunilAutomatico.modo(account, 'tempo_perdido') != 'off'
    avancar_negociacao(account) if Ramon::FunilAutomatico.modo(account, 'tempo_ultima_chance') != 'off'
  end

  def parados_em(account, label)
    etapa = account.lead_stages.find_by(label: label)
    return Lead.none if etapa.nil?

    Ramon::Cadencia.parados(account.leads.where(lead_stage: etapa))
  end

  def perder_sumidos(account)
    perdido = account.lead_stages.find_by(is_lost: true)
    return if perdido.nil?

    parados_em(account, 'fase-ultima-chance').find_each do |lead|
      etapa_anterior = lead.lead_stage_id
      Ramon::FunilAutomatico.executar(lead, peca: 'tempo_perdido', acao: 'mover_etapa', motivo: MOTIVO_PERDA, alvo: perdido.name,
                                            desfazer: { 'etapa_id' => etapa_anterior }) do
        lead.update!(lead_stage: perdido, lost_reason: MOTIVO_PERDA)
      end
    end
  end

  def avancar_negociacao(account)
    parados_em(account, 'fase-negociacao').find_each do |lead|
      Ramon::FunilRegras.mover_para_frente(lead, 'fase-ultima-chance', peca: 'tempo_ultima_chance',
                                                                       motivo: 'Negociação parada sem resposta')
    end
  end
end
