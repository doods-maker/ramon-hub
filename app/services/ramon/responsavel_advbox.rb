# Usuário do hub que é o responsável do processo do lead no ADVBOX (mesmo e-mail; Ramon::AgendaHojeService#usuario_do_hub).
# Usado pelo Ramon::ContratoApto para a tese sem advogado fixo. ADVBOX fora do ar, lead sem processo ou responsável sem
# usuário no hub: nil — quem chama decide o que fazer (lá, ficam os administradores).
module Ramon::ResponsavelAdvbox
  module_function

  def usuario_id(lead)
    processo = lead.custom_attributes&.dig('advbox', 'lawsuits_id')
    return if processo.blank?

    Ramon::AgendaHojeService.new(lead.account).usuario_do_hub(responsavel_id(processo))&.id
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError => e
    Rails.logger.warn("[Ramon::ResponsavelAdvbox] responsável do ADVBOX não lido (lead #{lead.id}): #{e.class}")
    nil
  end

  # GET /lawsuits/:id devolve o processo (às vezes dentro de "data")
  def responsavel_id(processo)
    resposta = Ramon::AdvboxClient.lawsuit(processo)
    resposta = resposta['data'] if resposta.is_a?(Hash) && resposta['data'].is_a?(Hash)
    resposta['responsible_id'] if resposta.is_a?(Hash) # formato inesperado = sem responsável (não trava a fila)
  end
end
