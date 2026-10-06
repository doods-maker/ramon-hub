# Números da tela Uso e custo (Inteligência): custo, tokens e erros do período por dia,
# função, assistente e modelo (ramon_llm_chamadas); o agente @claude (agente_execucoes,
# custo nominal = "equivalente") e os fluxos de IA de hoje (contador do Redis); e o
# provedor/modelo em vigor por função com as chaves do servidor (sim/não, nunca o valor).
class Ramon::IaUsoResumo
  ZONA = Ramon::CockpitMetrics::TIME_ZONE
  DIAS = { 'hoje' => 0, '7d' => 6, '30d' => 29 }.freeze # 'mes' = do dia 1 até hoje
  DIA_SQL = Arel.sql("DATE(created_at AT TIME ZONE 'UTC' AT TIME ZONE '#{ZONA}')")
  METRICAS = ['COUNT(*)', 'COALESCE(SUM(input_tokens), 0)', 'COALESCE(SUM(output_tokens), 0)', 'SUM(custo_usd)',
              "COUNT(*) FILTER (WHERE status = 'erro')"].map { |sql| Arel.sql(sql) }.freeze
  FUNCOES_ESCOLHA = %w[atendimento copiloto documentos agente].freeze

  def initialize(account, periodo)
    @account = account
    @periodo = DIAS.key?(periodo) || periodo == 'mes' ? periodo : '7d'
  end

  def perform
    {
      periodo: @periodo, de: inicio.to_date, ate: hoje, total: total, por_dia: por_dia,
      por_funcao: agrupar(:funcao), por_modelo: agrupar(:model), por_assistente: por_assistente,
      hoje_usd: Ramon::IaGastoAlerta.gasto_hoje(@account.id), teto_diario_usd: Ramon::IaGastoAlerta.teto(@account),
      agente: agente, fluxos: fluxos, escolhas: escolhas, chaves: Ramon::LlmEscolha.chaves
    }
  end

  private

  def agora = Time.find_zone!(ZONA).now

  def hoje = agora.to_date

  def inicio = @periodo == 'mes' ? agora.beginning_of_month : (agora - DIAS.fetch(@periodo).days).beginning_of_day

  def escopo = LlmChamada.where(account_id: @account.id, created_at: inicio..)

  def total
    linha(nil, escopo.pick(*METRICAS)).except(:chave).merge(sem_preco: escopo.where(custo_usd: nil).count)
  end

  def por_dia
    linhas = escopo.group(DIA_SQL).pluck(DIA_SQL, Arel.sql('SUM(custo_usd)'), Arel.sql('COUNT(*)'))
                   .to_h { |dia, custo, chamadas| [dia.to_date, [custo.to_f, chamadas]] }
    (inicio.to_date..hoje).map { |dia| { dia: dia, custo_usd: linhas.dig(dia, 0) || 0.0, chamadas: linhas.dig(dia, 1) || 0 } }
  end

  def agrupar(coluna)
    escopo.group(coluna).pluck(coluna, *METRICAS).map { |chave, *metricas| linha(chave, metricas) }
          .sort_by { |item| -(item[:custo_usd] || 0) }
  end

  def linha(chave, metricas)
    chamadas, entrada, saida, custo, erros = metricas
    { chave: chave, chamadas: chamadas.to_i, input_tokens: entrada.to_i, output_tokens: saida.to_i,
      custo_usd: custo&.to_f, erros: erros.to_i }
  end

  def por_assistente
    linhas = agrupar(:assistant_id).select { |item| item[:chave] }
    nomes = nomes_assistentes(linhas.pluck(:chave))
    linhas.map { |item| item.merge(nome: nomes[item[:chave]]) }
  end

  def nomes_assistentes(ids)
    return {} if ids.empty? || !ChatwootApp.enterprise?

    Captain::Assistant.where(account_id: @account.id, id: ids).pluck(:id, :name).to_h
  end

  # Custo do agente é NOMINAL (assinatura): a tela mostra como "equivalente".
  def agente
    execucoes = @account.agente_execucoes
    de_hoje = execucoes.where(created_at: agora.all_day)
    { hoje: de_hoje.consumiu_cota.count, teto: AgenteExecucao::TETO_DIA, custo_hoje_usd: de_hoje.sum(:custo_usd).to_f,
      execucoes_periodo: execucoes.where(created_at: inicio..).consumiu_cota.count,
      custo_periodo_usd: execucoes.where(created_at: inicio..).sum(:custo_usd).to_f }
  end

  # Contador e teto que o passo de IA dos fluxos usa (Ramon::Fluxos::Passos::Ia#cota!) — só leitura.
  def fluxos
    chave = "RAMON::FLUXO_IA::#{@account.id}::#{Time.find_zone!(Fluxo::ZONA).today}"
    { hoje: Redis::Alfred.get(chave).to_i, teto: ENV.fetch('RAMON_FLUXO_IA_DIA', Ramon::Fluxos::Passos::Ia::TETO_PADRAO).to_i }
  end

  def escolhas
    FUNCOES_ESCOLHA.map do |funcao|
      feature = Ramon::LlmEscolha::FEATURES[funcao]
      { funcao: funcao, feature: feature, fonte: Ramon::LlmEscolha.fonte(@account, funcao),
        salvo: feature && @account.captain_models&.dig(feature), modelos: modelos(feature) }
        .merge(Ramon::LlmEscolha.para(@account, funcao))
    end
  end

  # A assinatura (claude-vps) não está em feature nenhuma do llm.yml: nunca aparece aqui.
  def modelos(feature)
    return [] if feature.nil?

    Llm::Models.feature_config(feature)[:models].reject { |modelo| modelo[:coming_soon] }
  end
end
