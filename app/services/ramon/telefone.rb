# Celular BR em qualquer grafia: com/sem 55 e com/sem o 9º dígito (DDD + 9 + 8).
# Mesma regra do Ramon::Hoje::Escritorio.variantes_telefone (feat/tela-hoje).
module Ramon::Telefone
  module_function

  def variantes(numero)
    digitos = numero.to_s.gsub(/\D/, '')
    nacional = digitos.length > 11 && digitos.start_with?('55') ? digitos.delete_prefix('55') : digitos
    return [] if nacional.length < 10

    ddd = nacional[0, 2]
    local = nacional[2..]
    locais = [local, local.length == 9 && local.start_with?('9') ? local[1..] : "9#{local}"]
    locais.flat_map { |l| ["#{ddd}#{l}", "55#{ddd}#{l}"] }.uniq
  end

  # As variantes no formato do contact.phone_number (E.164, +55…).
  def e164(numero)
    variantes(numero).filter_map { |v| "+#{v}" if v.start_with?('55') }
  end

  # Contato já gravado com outra grafia do mesmo celular BR. Número estrangeiro
  # (sem +55) não gera variante: aí só vale o match exato de quem chama.
  def contato_por_variante(contatos, numero)
    return unless numero.to_s.start_with?('+55')

    contatos.find_by(phone_number: e164(numero))
  end
end
