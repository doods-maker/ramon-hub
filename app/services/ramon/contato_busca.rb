# Busca de contatos por número (tela Contatos e Pessoas/Linha da Vida): termo
# com 10+ dígitos depois de tirar a máscara acha também pelo CPF e por qualquer
# grafia do celular BR (com/sem 55 e com/sem o 9º dígito). Termo curto → nil.
module Ramon::ContatoBusca
  module_function

  def por_numero(contatos, termo)
    digitos = termo.to_s.gsub(/\D/, '')
    return if digitos.length < 10

    contatos.where(cpf: digitos).or(contatos.where(phone_number: Ramon::Telefone.e164(digitos)))
  end
end
