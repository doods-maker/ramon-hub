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

  # B4.1: o alvo também pode ser a tarefa da reunião (ciclo de lembretes) — lead e conversa vêm dela.
  def lead
    return alvo if alvo.is_a?(Lead)
    return alvo.lead if alvo.is_a?(LeadTask)
    return if alvo.nil?

    account.leads.where(conversation_id: alvo.id).reorder(id: :desc).first
  end

  def conversa = alvo.is_a?(Conversation) ? alvo : lead&.conversation

  def resumo_json
    {
      id: id, fluxo_id: fluxo_id, versao: versao&.numero, alvo_type: alvo_type, alvo_id: alvo_id,
      alvo_nome: alvo_nome, conversation_display_id: conversa&.display_id,
      lead_id: lead&.id, status: status, ensaio: ensaio, no_atual: no_atual, retomar_em: retomar_em,
      trilha: trilha, erro: erro, created_at: created_at, updated_at: updated_at
    }
  end

  private

  def alvo_nome = alvo.try(:name) || alvo.try(:contact)&.name || lead&.name
end
