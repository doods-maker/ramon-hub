# Conferência de fases: 1 linha por processo judicial ativo do ADVBOX com a etapa de lá ao lado do que o
# Painel do Cliente mostra (tribunal + tarefas), a etapa sugerida e a marcação da equipe. Refeita à noite
# pelo Ramon::ConferenciaFasesJob; o administrador aplica as marcadas no ADVBOX.
class CreateRamonConferenciasFase < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_conferencias_fase do |t|
      colunas_do_processo(t)
      colunas_da_marcacao(t)
      t.timestamps
    end
    add_index :ramon_conferencias_fase, [:account_id, :lawsuit_id], unique: true
    add_index :ramon_conferencias_fase, [:account_id, :grupo]
  end

  private

  def colunas_do_processo(tabela)
    tabela.bigint :account_id, null: false
    tabela.bigint :lawsuit_id, null: false
    %i[numero cliente responsavel etapa_advbox fase_advbox painel_titulo fase_painel].each { |c| tabela.string c }
    tabela.bigint :etapa_advbox_id
    tabela.string :grupo, null: false
    tabela.jsonb :tribunal
    tabela.jsonb :agenda, null: false, default: []
    tabela.date :ultimo_andamento
    tabela.jsonb :sugestao
  end

  def colunas_da_marcacao(tabela)
    tabela.string :painel_marca
    tabela.boolean :atualizar, null: false, default: false
    tabela.text :obs
    tabela.bigint :marcado_por_id
    tabela.datetime :marcado_em
    tabela.datetime :aplicado_em
    tabela.bigint :aplicado_por_id
    tabela.string :erro_aplicacao
  end
end
