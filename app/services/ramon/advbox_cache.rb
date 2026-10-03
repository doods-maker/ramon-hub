# Leitura do ADVBOX das telas do dia (agenda da Recepção, semana da advogada,
# e-mails dos usuários). Cota de 500 chamadas/dia compartilhada, então:
# - cache por chave;
# - fora do expediente (antes das 7h, depois das 20h e fim de semana, em SP) não
#   chama: usa o cache e, sem cache, devolve vazio (não é "fora");
# - falhou → pausa de 10 min (cache negativo): ninguém chama, todo mundo recebe
#   UnavailableError na hora.
module Ramon::AdvboxCache
  module_function

  ERROS = [Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError].freeze
  PAUSA_CHAVE = 'ramon/advbox_fora'.freeze
  PAUSA = 10.minutes
  EXPEDIENTE = (7...20)

  def buscar(chave, expires_in:, &)
    valor = Rails.cache.read(chave)
    return valor unless valor.nil?
    return [] unless expediente?
    raise Ramon::AdvboxClient::UnavailableError, 'ADVBOX em pausa depois de uma falha' if Rails.cache.exist?(PAUSA_CHAVE)

    buscar_agora(chave, expires_in, &)
  end

  def buscar_agora(chave, expires_in)
    valor = yield
    Rails.cache.write(chave, valor, expires_in: expires_in)
    valor
  rescue *ERROS
    Rails.cache.write(PAUSA_CHAVE, true, expires_in: PAUSA)
    raise
  end

  def expediente?
    agora = Time.find_zone!(Chegada::ZONA).now
    !agora.on_weekend? && EXPEDIENTE.cover?(agora.hour)
  end
end
