# Celular BR em qualquer grafia: com/sem 55 e com/sem o 9º dígito (DDD + 9 + 8).
# Usado pela tela Hoje (Recepção) e pelo painel de cliente da conversa.
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
end
