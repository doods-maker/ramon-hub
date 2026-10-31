module Ramon::Peticionamento::Cnj
  TRIBUNAIS = { '404' => 'trf4', '824' => 'tjsc', '512' => 'trt12' }.freeze

  # "NNNNNNN-DD.AAAA.J.TR.OOOO" a partir de qualquer texto com 20 dígitos; senão nil.
  def self.normalizar(texto)
    d = texto.to_s.gsub(/\D/, '')
    return nil unless d.length == 20

    "#{d[0, 7]}-#{d[7, 2]}.#{d[9, 4]}.#{d[13]}.#{d[14, 2]}.#{d[16, 4]}"
  end

  # Dígito verificador módulo 97 (Res. CNJ 65/2008).
  def self.valido?(numero)
    n = normalizar(numero)
    return false if n.nil?

    d = n.delete('^0-9')
    base = "#{d[0, 7]}#{d[9, 11]}00".to_i # N + A + JTR + O + "00"
    d[7, 2].to_i == 98 - (base % 97)
  end

  def self.tribunal(numero)
    n = normalizar(numero)
    return nil if n.nil?

    d = n.delete('^0-9')
    TRIBUNAIS[d[13, 3]]
  end
end
