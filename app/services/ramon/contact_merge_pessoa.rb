# FORK(ramon): a mesclagem de contatos leva junto o que é do fork.
# - Leads: o contato que sai é destruído e o has_many :leads (dependent: :nullify)
#   deixaria o lead órfão — e o próximo contato abriria um lead duplicado.
# - Campos de pessoa (CPF, nascimento, sexo), com preferência do contato base,
#   como o ContactMergeAction já faz com os campos nativos.
# Entra por prepend no ContactMergeAction (gancho de 1 linha no arquivo nativo).
module Ramon::ContactMergePessoa
  CAMPOS_PESSOA = %w[cpf data_nascimento sexo].freeze

  private

  def merge_and_remove_mergee_contact
    # rubocop:disable Rails/SkipsModelValidations
    Lead.where(contact_id: @mergee_contact.id).update_all(contact_id: @base_contact.id)
    pessoa = campos_pessoa(@mergee_contact).merge(campos_pessoa(@base_contact))
    # CPF é único por conta: sai do contato que some antes de ir para o base.
    @mergee_contact.update_columns(cpf: nil) if @mergee_contact.cpf.present?
    # rubocop:enable Rails/SkipsModelValidations
    super
    @base_contact.update!(pessoa) if pessoa.present?
  end

  def campos_pessoa(contact)
    contact.attributes.slice(*CAMPOS_PESSOA).compact_blank
  end
end
