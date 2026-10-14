# Modo "sozinha até o contrato" (spec roteiro §3.7, F3): o contrato sai na hora, sem a sugestão no Cockpit — só nesse
# modo, só com modelo de contrato na tese e com o cadastro confirmado (nome completo, CPF e rua/número/cidade do
# "Dados do contrato" do painel). Gerou → o link volta para a IA enviar; o callback do Lead (zapsign mudou) encerra o
# modo. Faltou algo ou o ZapSign falhou → o modo encerra com o motivo e a tool deixa a sugestão de sempre.
module Ramon::ContratoAutomatico
  MODO = 'piloto_ate_contrato'.freeze
  # Endereço da colheita vem numa string só (vai inteiro na rua): sem número e cidade não conta como confirmado.
  OBRIGATORIOS = { '{{CPF}}' => 'CPF', '{{rua}}' => 'rua', '{{número}}' => 'número', '{{cidade}}' => 'cidade' }.freeze

  module_function

  # @return nil (fora do modo) | { link: } | { falta: [..] }
  def preparar(lead)
    return unless lead.conversation && Ramon::CopilotoModo.of(lead.conversation) == MODO

    modelo = lead.thesis&.zapsign_template_id
    falta = faltando(lead, modelo)
    return parar(lead, falta) if falta.any?

    { link: Ramon::ZapsignContractService.new(lead, template_id: modelo).perform['sign_url'] }
  rescue Ramon::ZapsignContractService::ConflictError, Ramon::ZapsignClient::RequestError,
         Ramon::ZapsignClient::UnavailableError => e
    parar(lead, ["ZapSign: #{e.message.to_s.truncate(120)}"])
  end

  def faltando(lead, modelo)
    return ['modelo de contrato da tese'] if modelo.blank?

    vazios = Ramon::ZapsignContractService.new(lead, template_id: modelo).preview['faltando']
    nome = lead.contact&.name.presence || lead.name
    (nome.to_s.split.size < 2 ? ['nome completo'] : []) + OBRIGATORIOS.slice(*vazios).values
  end

  def parar(lead, falta)
    Ramon::CopilotoLimite.encerrar(lead, 'contrato', "contrato nao saiu na hora: falta #{falta.join(', ')}")
    { falta: falta }
  end
end
