# Visão geral da área Inteligência (I-VG1–3): junta o que o hub já grava —
# views bi_ia (rascunhos, 1ª resposta, transferências), sugestões pendentes da
# IA e a trilha do agente Claude. Leitura pura. Vigia, Ferramentas 24h e Base
# de conhecimento a tela busca nos endpoints que já existem (ramon_watchdog,
# captain_tool_runs, captain/assistants/stats) — este não toca Captain::* e
# roda igual no CI FOSS.
class Api::V1::Accounts::RamonInteligenciaController < Api::V1::Accounts::BaseController
  JANELA = 30.days
  # D7: o padrão vira piloto_limitado depois de ~20 conversas revisadas.
  META_PILOTO = 20
  TETO_AGENTE = AgenteExecucao::TETO_DIA
  REVISADOS = %w[igual editado descartado].freeze

  SQL_RASCUNHOS = <<~SQL.squish.freeze
    SELECT desfecho, COUNT(*) AS total FROM bi_ia_rascunhos
    WHERE account_id = ? AND criado_em >= ? GROUP BY desfecho
  SQL
  SQL_PILOTO = <<~SQL.squish.freeze
    SELECT COUNT(DISTINCT conversation_id) AS conversas, COUNT(*) AS revisados,
           COUNT(*) FILTER (WHERE desfecho = 'igual') AS iguais
    FROM bi_ia_rascunhos WHERE account_id = ? AND desfecho IN (?)
  SQL
  # Mediana, não média: uma conversa que chegou de madrugada não distorce.
  SQL_RESPOSTA = <<~SQL.squish.freeze
    SELECT com_ia, COUNT(*) AS conversas,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY minutos_primeira_resposta) AS mediana
    FROM bi_ia_conversas
    WHERE account_id = ? AND iniciada_em >= ? AND minutos_primeira_resposta IS NOT NULL
    GROUP BY com_ia
  SQL
  SQL_TRANSFERENCIAS = <<~SQL.squish.freeze
    SELECT conversation_id FROM bi_ia_conversas
    WHERE account_id = ? AND iniciada_em >= ? AND handoffs > 0
    ORDER BY iniciada_em DESC
  SQL
  # I-X6: a última rodada concluída do caderno de provas, por assistente (SQL: ramon_ia_rodadas é do enterprise).
  SQL_CADERNO = <<~SQL.squish.freeze
    SELECT DISTINCT ON (r.assistant_id) r.assistant_id, a.name, r.passou, r.total,
           EXTRACT(EPOCH FROM r.created_at)::bigint AS em
    FROM ramon_ia_rodadas r JOIN captain_assistants a ON a.id = r.assistant_id
    WHERE r.account_id = ? AND r.status = 'concluida'
    ORDER BY r.assistant_id, r.created_at DESC
  SQL

  before_action :current_account
  before_action :check_authorization

  def show
    render json: {
      rascunhos: rascunhos, piloto: piloto, primeira_resposta: primeira_resposta,
      transferencias: transferencias, aprovacoes: aprovacoes, agente: agente, caderno: caderno
    }
  end

  private

  # Mesmas permissões do Centro de Comando e do Vigia (admin + agent).
  def check_authorization
    authorize(:ramon_dashboard, :show?)
  end

  def linhas(sql, *binds)
    ActiveRecord::Base.connection.select_all(ActiveRecord::Base.sanitize_sql_array([sql, *binds])).to_a
  end

  # desfecho => quantos: igual, editado, descartado, sem_resposta, pendente.
  def rascunhos
    linhas(SQL_RASCUNHOS, Current.account.id, JANELA.ago).to_h { |linha| [linha['desfecho'], linha['total'].to_i] }
  end

  # Régua da D7 (desde sempre): conversas com rascunho revisado e % enviado sem correção.
  def piloto
    linha = linhas(SQL_PILOTO, Current.account.id, REVISADOS).first
    revisados = linha['revisados'].to_i
    {
      conversas: linha['conversas'].to_i, meta: META_PILOTO,
      sem_correcao_pct: revisados.zero? ? nil : (linha['iguais'].to_i * 100.0 / revisados).round
    }
  end

  def primeira_resposta
    linhas(SQL_RESPOSTA, Current.account.id, JANELA.ago).to_h do |linha|
      [linha['com_ia'] ? 'com_ia' : 'sem_ia', { conversas: linha['conversas'].to_i, mediana_min: linha['mediana'].to_f.round(1) }]
    end
  end

  # handoffs é 0/1 por conversa (bi_ia_conversas); a tela linka as 5 mais novas.
  def transferencias
    ids = linhas(SQL_TRANSFERENCIAS, Current.account.id, JANELA.ago).pluck('conversation_id')
    { total: ids.size, conversas: Current.account.conversations.where(id: ids.first(5)).order(id: :desc).pluck(:display_id) }
  end

  # Tipo = a ação em sistema (zapsign, advbox, reuniao, perdido) ou o kind (draft, move_stage, alert).
  def aprovacoes
    pendentes = Current.account.copilot_suggestions.pending
    { sugestoes: pendentes.count, sugestoes_por_tipo: pendentes.group(Arel.sql("COALESCE(payload->>'acao', kind)")).count }
  end

  # "Hoje" no fuso de Brasília — o servidor roda em UTC.
  def agente
    execucoes = Current.account.agente_execucoes
    hoje = execucoes.de_hoje
    {
      hoje: hoje.consumiu_cota.count, teto: TETO_AGENTE, problemas_hoje: hoje.where.not(status: 'ok').count,
      ultima_em: execucoes.maximum(:created_at)
    }
  end

  def caderno
    linhas(SQL_CADERNO, Current.account.id).map do |linha|
      { assistant_id: linha['assistant_id'].to_i, nome: linha['name'], passou: linha['passou'].to_i,
        total: linha['total'].to_i, em: linha['em'].to_i }
    end
  end
end
