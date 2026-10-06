# Rodada dos casos de teste de um assistente: roda em fila baixa, um caso por
# vez, e grava o progresso a cada caso (a tela faz polling). resultados = um
# item por caso: caso_id, titulo, passou, motivos, resposta, ferramentas,
# handoff, duracao_ms.
class Captain::IaRodada < ApplicationRecord
  self.table_name = 'ramon_ia_rodadas'

  STATUSES = %w[fila rodando concluida erro].freeze
  ATIVOS = %w[fila rodando].freeze
  # ponytail: estimativa fixa do mapa de custos (2–4 chamadas + juiz no
  # deepseek). Upgrade = somar o uso real quando a tarefa de custo gravar tokens.
  CUSTO_POR_CASO_USD = 0.05
  SEGUNDOS_POR_CASO = 20
  # Job morto (deploy no meio, OOM) deixa rodada "rodando" para sempre e
  # trava o assistente: sem progresso há tanto tempo, vira erro.
  TRAVADA_APOS = 30.minutes

  belongs_to :account
  belongs_to :assistant, class_name: 'Captain::Assistant'
  belongs_to :disparado_por, class_name: 'User', optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :ativas, -> { where(status: ATIVOS) }
  scope :recentes, -> { order(created_at: :desc) }

  def self.estimativa(casos)
    { casos: casos, custo_usd: (casos * CUSTO_POR_CASO_USD).round(2), segundos: casos * SEGUNDOS_POR_CASO }
  end

  def self.destravar!(assistant_id)
    travadas = ativas.where(assistant_id: assistant_id).where(updated_at: ...TRAVADA_APOS.ago)
    travadas.update_all(status: 'erro', erro: 'Parou sem progresso.', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def resumo
    as_json(except: %w[resultados account_id])
  end

  def passou_por_caso
    resultados.to_h { |item| [item['caso_id'], item['passou']] }
  end

  # Contra a última rodada concluída antes desta: o que piorou (passava e
  # agora falha) e o que melhorou. Caso novo ou removido fica de fora.
  def comparacao
    base = self.class.where(assistant_id: assistant_id, status: 'concluida').where(id: ...id).order(id: :desc).first
    return if base.blank?

    antes = base.passou_por_caso
    agora = passou_por_caso.select { |caso_id, _ok| antes.key?(caso_id) }
    { rodada_id: base.id, passou: base.passou, total: base.total,
      pioraram: agora.select { |caso_id, ok| antes[caso_id] && !ok }.keys,
      melhoraram: agora.select { |caso_id, ok| ok && !antes[caso_id] }.keys }
  end
end
