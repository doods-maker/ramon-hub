# Uso e custo da IA (tela Inteligência → Uso e custo): uma linha por chamada de LLM,
# gravada nos pontos únicos (Ramon::LlmClient, instrumentação do Captain, runner do
# agente). custo_usd é calculado na gravação pela tabela de preços do RubyLLM
# (nil = modelo sem preço conhecido). O agente Claude da VPS segue na própria
# trilha (agente_execucoes), agora com tokens e custo nominal da assinatura.
class CreateRamonLlmChamadas < ActiveRecord::Migration[7.1]
  def change
    criar_chamadas
    add_column :agente_execucoes, :input_tokens, :integer
    add_column :agente_execucoes, :output_tokens, :integer
    add_column :agente_execucoes, :custo_usd, :decimal, precision: 12, scale: 6
  end

  private

  def criar_chamadas
    create_table :ramon_llm_chamadas do |t|
      t.bigint :account_id, null: false
      t.string :funcao, null: false
      t.string :origem, null: false, default: 'real'
      t.bigint :assistant_id
      t.string :provider
      t.string :model
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.decimal :custo_usd, precision: 12, scale: 6
      t.integer :duracao_ms
      t.string :status, null: false, default: 'ok'
      t.string :erro
      t.bigint :conversation_id
      t.bigint :lead_id
      t.datetime :created_at, null: false
      t.index [:account_id, :created_at]
    end
  end
end
