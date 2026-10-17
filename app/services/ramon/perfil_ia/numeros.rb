# Números por Etapa da tela "Como a IA atende" (spec, sugestão 1): últimos 30 dias, por alvo e Etapa, lidos dos carimbos
# ramon_piloto (enviada pela IA), ramon_ia_rascunho (nota-rascunho) e ramon_rascunho_ia (resposta humana que usou
# rascunho). Mensagem sem alvo/etapa no carimbo (de antes da gravação) não conta: a tela mostra "sem dados ainda".
module Ramon::PerfilIa::Numeros
  JANELA = 30.days
  # O META_PILOTO da Visão geral: abaixo disso o "igual" ainda é sorte.
  MINIMO_REVISADOS = 20
  IGUAL_MINIMO = 0.9
  # content_attributes é json gravado como STRING JSON em boa parte das linhas (ver db/views/bi_ia_*_v02.sql).
  ATTRS = "(content_attributes #>> '{}')::jsonb".freeze
  CARIMBO = "COALESCE(#{%w[ramon_piloto ramon_ia_rascunho ramon_rascunho_ia].map { |k| "#{ATTRS}->'#{k}'" }.join(', ')})".freeze
  COLUNAS = [
    "#{CARIMBO}->>'alvo'", "#{CARIMBO}->>'etapa'",
    "COUNT(*) FILTER (WHERE #{ATTRS}->'ramon_piloto' IS NOT NULL)",
    *%w[igual editado descartado].map { |d| "COUNT(*) FILTER (WHERE #{ATTRS}->'ramon_rascunho_ia'->>'desfecho' = '#{d}')" },
    "COUNT(*) FILTER (WHERE #{CARIMBO}->>'handoff' = 'true')"
  ].map { |sql| Arel.sql(sql) }.freeze

  module_function

  # { etapa_chave => { enviadas:, rascunhos: { igual:, editado:, descartado: }, chamou_equipe:, sugerir_sozinha: } };
  # Etapa sem nada = chave ausente.
  def de(account, alvo) = todos(account).fetch(alvo, {})

  # { alvo => { etapa => ... } } numa consulta só (agrupada por alvo e Etapa).
  # Um content_attributes que não é JSON quebra o cast na consulta: a tela fica sem números ("sem dados ainda"), não cai.
  def todos(account)
    contar(account, linhas(account))
  rescue ActiveRecord::StatementInvalid, JSON::ParserError => e
    Rails.logger.warn("[Ramon::PerfilIa::Numeros] sem números (conta #{account.id}): #{e.class}: #{e.message}")
    {}
  end

  def contar(account, linhas)
    etapas = account.lead_stages.where(is_won: false, is_lost: false).index_by { |e| Ramon::PerfilIa.chave_da_etapa(e) }
    perfis = Hash.new { |h, alvo| h[alvo] = perfil(account, alvo) }
    linhas.each_with_object({}) do |(alvo, etapa, *contagens), saida|
      (saida[alvo] ||= {})[etapa] = numeros(*contagens).tap do |n|
        n[:sugerir_sozinha] = sugerir?(perfis[alvo], etapas[etapa], n[:rascunhos])
      end
    end
  end

  # [alvo, etapa, enviadas, igual, editado, descartado, chamou_equipe] por alvo e Etapa.
  # unscope(:order): o default_scope do Message ordena por created_at, que o GROUP BY não aceita.
  def linhas(account)
    account.messages.unscope(:order).where(created_at: JANELA.ago..).where("#{CARIMBO}->>'alvo' IS NOT NULL")
           .group(COLUNAS[0], COLUNAS[1]).pluck(*COLUNAS)
  end

  def numeros(enviadas, igual, editado, descartado, chamou)
    { enviadas: enviadas, rascunhos: { igual: igual, editado: editado, descartado: descartado }, chamou_equipe: chamou }
  end

  # Etapa (aberta) em rascunho no perfil gravado do alvo, revisados suficientes e quase todos enviados sem edição.
  def sugerir?(perfil, etapa, rascunhos)
    revisados = rascunhos.values.sum
    return false if perfil.nil? || etapa.nil? || revisados < MINIMO_REVISADOS

    perfil.estado(etapa) == :rascunho && rascunhos[:igual].fdiv(revisados) >= IGUAL_MINIMO
  end

  # O Perfil gravado do alvo do carimbo; tese/caixa que hoje segue o padrão (ou alvo estranho) = nil, sem sugestão.
  def perfil(account, alvo)
    tipo, id = alvo.split(':')
    cfg = case tipo
          when 'padrao' then Ramon::PerfilIa.cfg_salvo(account, 'padrao') || Ramon::PerfilIa::INICIAL
          when 'tese', 'caixa' then Ramon::PerfilIa.cfg_salvo(account, "#{tipo}s", id)
          end
    # lead em branco só dá a conta ao Perfil (account_id: não entra no cache account.leads)
    Ramon::PerfilIa.new(nil, Lead.new(account_id: account.id), alvo, cfg, tipo.to_sym) if cfg
  end
end
