# Contrato na hora (Perfil da IA, ação contrato_zapsign): sai sem a sugestão no Cockpit — só com a Permissão sozinha e
# a Etapa antes do Marcador (PerfilIa#direto?), com conversa, com modelo de contrato na tese e com o cadastro confirmado
# (nome completo, CPF e rua/número/cidade do "Dados do contrato" do painel). Gerou → o link volta para a IA enviar.
# Faltou algo ou o ZapSign falhou → { falta: } com o motivo e a tool deixa a sugestão de sempre.
module Ramon::ContratoAutomatico
  # Endereço da colheita vem numa string só (vai inteiro na rua): sem número e cidade não conta como confirmado.
  OBRIGATORIOS = { '{{CPF}}' => 'CPF', '{{rua}}' => 'rua', '{{número}}' => 'número', '{{cidade}}' => 'cidade' }.freeze

  module_function

  # @return nil (o perfil não deixa) | { link: } | { falta: [..] }
  def preparar(lead)
    return unless lead.conversation && Ramon::PerfilIa.de(lead).direto?('contrato_zapsign')

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

    dados_faltando(lead)
  end

  # O que falta no cadastro para o contrato sair sozinho — também guia a IA que coleta os dados (Ramon::DadosContrato).
  # A prévia não depende do modelo (variaveis é igual para todos); quem já tem os vazios passa e não calcula de novo.
  def dados_faltando(lead, vazios = Ramon::ZapsignContractService.new(lead).preview['faltando'])
    (lead.nome_completo? ? [] : ['nome completo']) + OBRIGATORIOS.slice(*vazios).values
  end

  def parar(lead, falta)
    Ramon::CopilotoLimite.encerrar(lead, Ramon::CopilotoLimite::CONTRATO_FALHOU, falta.join(', '))
    { falta: falta }
  end
end
