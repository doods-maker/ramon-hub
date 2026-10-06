# Gatilhos de relógio (spec §4.1), chamados a cada minuto pelo Ramon::FluxoRelogioJob:
# - relogio: todo dia a partir de HH:MM, cada lead de um grupo (etapa/tese/responsável);
# - lead_parado: 1×/dia a partir de HH:MM (padrão 11:00), leads parados na etapa — 1 vez por parada.
# `ultimo_disparo_em` (fuso SP) garante 1 disparo por fluxo por dia; se o minuto exato passar
# (deploy, hub fora do ar), dispara quando o relógio voltar, no mesmo dia.
module Ramon::Fluxos::Relogio
  HORA_PADRAO = '11:00'.freeze
  MAX_LEADS = 500 # ponytail: por fluxo por dia; paginar se um grupo passar disso

  module_function

  def disparar_do_dia(agora = Time.find_zone!(Fluxo::ZONA).now)
    Fluxo.executaveis.where(gatilho_tipo: %w[relogio lead_parado]).includes(:versao_publicada).find_each do |fluxo|
      config = Ramon::Fluxos::Grafo.new(fluxo.versao_publicada.grafo).gatilho['config'] || {}
      next unless na_hora?(config, agora) && reivindicar_dia(fluxo, agora)

      grupo(fluxo, config).limit(MAX_LEADS).each do |lead|
        # ponytail: 1 count por lead; agregar se grupos grandes com limite virarem rotina
        break if fluxo.modo == 'normal' && fluxo.limite_atingido?

        disparar(fluxo, lead)
      end
    end
  end

  # Erro num lead não derruba os outros leads nem os outros fluxos (o dia já foi reivindicado).
  def disparar(fluxo, lead)
    Ramon::Fluxos::Disparo.new(fluxo, lead, {}, nil).iniciar
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: fluxo.account).capture_exception
    Rails.logger.warn("[Ramon::Fluxos::Relogio] fluxo #{fluxo.id} lead #{lead.id}: #{e.class}")
  end

  def na_hora?(config, agora)
    hora, minuto = (config['hora'].presence || HORA_PADRAO).split(':').map(&:to_i)
    agora >= agora.change(hour: hora, min: minuto)
  end

  # Marca o dia ANTES de disparar, num UPDATE condicional: dois relógios no mesmo minuto não duplicam.
  def reivindicar_dia(fluxo, agora)
    Fluxo.where(id: fluxo.id).where('ultimo_disparo_em IS NULL OR ultimo_disparo_em < ?', agora.beginning_of_day)
         .update_all(ultimo_disparo_em: agora) == 1 # rubocop:disable Rails/SkipsModelValidations
  end

  def grupo(fluxo, config)
    fluxo.gatilho_tipo == 'lead_parado' ? parados(fluxo, config) : filtrados(fluxo.account, config)
  end

  # Sem etapa marcada: leads abertos (nem ganho nem perdido). Com etapa: inclusive pós-ganho.
  def filtrados(account, config)
    etapas, teses, pessoas = %w[etapa_ids tese_ids responsavel_ids].map { |k| Array(config[k]).map(&:to_i) }
    leads = etapas.any? ? account.leads.funil.where(lead_stage_id: etapas) : account.leads.open
    leads = leads.where(thesis_id: teses) if teses.any?
    leads = leads.where(sdr_id: pessoas).or(leads.where(closer_id: pessoas)) if pessoas.any?
    leads.reorder(:id)
  end

  # 1 vez por parada: lead que já teve execução deste fluxo depois de entrar na etapa fica de fora.
  def parados(fluxo, config)
    dias = config['dias'].to_i
    leads = fluxo.account.leads.open
    leads = dias.positive? ? leads.where(stage_entered_at: ...dias.days.ago) : Ramon::Cadencia.parados(leads)
    ja = FluxoExecucao.where(fluxo_id: fluxo.id, alvo_type: 'Lead', ensaio: false)
                      .where('ramon_fluxo_execucoes.alvo_id = leads.id AND ramon_fluxo_execucoes.created_at >= leads.stage_entered_at')
    leads.where(ja.arel.exists.not).reorder(:id)
  end
end
