# Leitura pura: o placar do funil de hoje (meta, conversao com gargalo, SLA e
# perdas por tese), a partir do Ramon::CockpitMetrics, em texto curto.
class Captain::Tools::FunilHojeTool < Captain::Tools::BasePublicTool
  description 'Placar do funil comercial: meta do dia, conversao etapa a etapa (com o gargalo), SLA de 1a resposta ' \
              'de hoje e as teses que mais perdem (90 dias). Use quando perguntarem como esta o funil ou o dia.'

  TOP_TESES = 3

  def perform(_tool_context)
    log_tool_usage('funil_hoje')
    metrics = Ramon::CockpitMetrics.new(@assistant.account)
    [meta(metrics.goal), conversao(metrics.conversion), sla(metrics.sla_today), perdas(metrics.losses_by_thesis)].join("\n\n")
  end

  private

  def meta(goal)
    "Meta do dia: #{goal[:done]} de #{goal[:target]} atividades concluidas."
  end

  def conversao(rows)
    return 'Conversao (90d): sem dados de etapa.' if rows.blank?

    com_entrada = rows.select { |r| r[:entered].positive? }
    gargalo = com_entrada.min_by { |r| r[:rate] }
    linhas = rows.map do |r|
      "- #{r[:name]}: #{r[:advanced]}/#{r[:entered]} avancaram (#{r[:rate]}%)#{' <- gargalo' if r.equal?(gargalo)}"
    end
    "Conversao etapa a etapa (90d):\n#{linhas.join("\n")}"
  end

  def sla(sla)
    media = sla[:avg_first_response_minutes]
    "SLA de 1a resposta hoje: #{sla[:breached]} estouradas; media #{media ? "#{media} min" : 'sem respostas ainda'}."
  end

  def perdas(losses)
    teses = losses[:theses].first(TOP_TESES)
    return "Perdas por tese (#{losses[:window_days]}d): nenhuma." if teses.blank?

    linhas = teses.map do |t|
      motivo = t[:reasons].first
      "- #{t[:name]}: #{t[:total]} perdidos (antes: #{t[:prev_total]})#{"; motivo mais comum: #{motivo[:reason]} (#{motivo[:count]})" if motivo}"
    end
    "Perdas por tese (#{losses[:window_days]}d, top #{TOP_TESES}):\n#{linhas.join("\n")}"
  end
end
