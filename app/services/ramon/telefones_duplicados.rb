# Contatos duplicados pela grafia do celular BR (com/sem 55, com/sem o 9º
# dígito). SÓ LEITURA: lista os grupos para revisão; quem mescla é a pessoa,
# pela tela de Contatos (aba Mesclar).
class Ramon::TelefonesDuplicados
  def initialize(account)
    @account = account
  end

  # [[contato, contato, ...], ...] — cada grupo é o mesmo celular em grafias diferentes.
  def grupos
    @account.contacts.where('phone_number LIKE ?', '+55%').select(:id, :name, :phone_number)
            .group_by { |contato| Ramon::Telefone.variantes(contato.phone_number).min }
            .reject { |chave, contatos| chave.nil? || contatos.size < 2 }
            .values
  end
end
