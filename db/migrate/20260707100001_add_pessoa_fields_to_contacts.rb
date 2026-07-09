class AddPessoaFieldsToContacts < ActiveRecord::Migration[7.1]
  def change
    add_column :contacts, :cpf, :string
    add_column :contacts, :data_nascimento, :date
    add_column :contacts, :sexo, :string
    add_index :contacts, [:account_id, :cpf], unique: true, where: 'cpf IS NOT NULL',
                                              name: 'uniq_cpf_per_account_contact'
  end
end
