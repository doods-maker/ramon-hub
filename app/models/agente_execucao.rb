# Trilha de cada execução do agente do hub (Claude na VPS): pedido, status,
# resumo e ações determinísticas feitas pelo runner. Alimenta o Metabase.
class AgenteExecucao < ApplicationRecord
  # "execucao" não pluraliza em inglês: o Rails inferiria agente_execucaos.
  self.table_name = 'agente_execucoes'

  STATUS = %w[ok erro limite cap timeout].freeze
  # ponytail: o teto de verdade mora no runner da VPS (CAP_DIA=30); aqui só desenha a barra.
  TETO_DIA = 30
  # Resumo que o runner grava quando NÃO roda o claude (cap do dia ou pausa por limite):
  # essas linhas não gastaram cota. "limite" detectado DEPOIS de rodar gastou (outro resumo).
  NAO_EXECUTOU = 'Cap diário atingido%'.freeze

  scope :consumiu_cota, -> { where('resumo IS NULL OR resumo NOT LIKE ?', NAO_EXECUTOU) }
  # "Hoje" no fuso de Brasília — o servidor roda em UTC. Visão geral e aba Agente Claude.
  scope :de_hoje, -> { where(created_at: Time.find_zone(Ramon::CockpitMetrics::TIME_ZONE).now.beginning_of_day..) }

  belongs_to :account
  belongs_to :conversation, optional: true
  belongs_to :lead, optional: true

  validates :pedido, presence: true
  validates :status, inclusion: { in: STATUS }
end
