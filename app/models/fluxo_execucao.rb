# Uma passada de um Fluxo por um lead ou conversa. `trilha` = passos percorridos
# (o que acende o caminho no quadro); `contexto` = gatilho, variáveis, etapa inicial.
# Ensaio: não executa ações; versao_id nulo quando ensaia o rascunho (contexto['grafo']).
class FluxoExecucao < ApplicationRecord
  self.table_name = 'ramon_fluxo_execucoes'

  STATUS = %w[rodando esperando concluida falhou cancelada].freeze

  belongs_to :account
  belongs_to :fluxo
  belongs_to :versao, class_name: 'FluxoVersao', optional: true
  belongs_to :alvo, polymorphic: true, optional: true

  validates :status, inclusion: { in: STATUS }

  def grafo = Ramon::Fluxos::Grafo.new(contexto['grafo'] || versao&.grafo)

  def lead
    return alvo if alvo.is_a?(Lead)
    return if alvo.nil?

    account.leads.where(conversation_id: alvo.id).reorder(id: :desc).first
  end

  def conversa = alvo.is_a?(Conversation) ? alvo : alvo&.conversation
end
