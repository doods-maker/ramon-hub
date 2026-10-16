# Passo que a IA deduz da conversa, sem perguntar ao lead (ex.: o enquadramento das trabalhistas). Antes isso se lia
# no texto da orientação ("Não pergunte..."); agora é uma marca do passo: ele não entra no bloco de perguntas nem ganha
# botões, mesmo se alguém reescrever a orientação. Os passos de hoje com "Não pergunte" no começo já saem marcados.
class AddSemPerguntarToRoteiroPassos < ActiveRecord::Migration[7.1]
  def up
    add_column :ramon_roteiro_passos, :sem_perguntar, :boolean, default: false, null: false
    execute "UPDATE ramon_roteiro_passos SET sem_perguntar = true WHERE orientacao ~* '^n[ãa]o pergunte'"
  end

  def down
    remove_column :ramon_roteiro_passos, :sem_perguntar
  end
end
