# Opções do roteiro como botões/lista no WhatsApp, por tese (decisão do Eduardo 15/10): desligado | ligado | teste_ab.
class AddOpcoesBotoesToTheses < ActiveRecord::Migration[7.1]
  def change
    add_column :theses, :opcoes_botoes, :string, default: 'desligado', null: false
  end
end
