# Orientação escrita ao negar um pedido da esteira (ADR 0014). Fica só até o hook ler.
class AddMotivoToRamonAprovacoesAgente < ActiveRecord::Migration[7.1]
  def change
    add_column :ramon_aprovacoes_agente, :motivo, :text
  end
end
