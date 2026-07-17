# Item 21 (metade ZapSign, fluxo A — decisão do Eduardo 15/07/2026): botão no
# painel do lead gera contrato + procuração pré-preenchidos no ZapSign (o modelo
# único da conta já embute a procuração como doc extra) e devolve o link de
# assinatura pra reunião. Nada é enviado ao cliente automaticamente.
class Ramon::ZapsignContractService
  # Modelo "Contrato honorarios Aux. Acidente" (GET /templates, 15/07/2026).
  # ponytail: fork single-tenant — id em constante; virar config na 2ª tese com modelo.
  TEMPLATE_ID = 'ab138291-2e38-4232-96c5-47a87c814819'.freeze

  BLANK = '________'.freeze
  MESES = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro].freeze

  def initialize(lead)
    @lead = lead
    @contact = lead.contact
  end

  # => { 'sign_url' =>, 'doc_token' =>, 'faltando' => [...] }
  def perform
    result = Ramon::ZapsignClient.create_doc_from_template(payload)
    stored = {
      'doc_token' => result['token'],
      'sign_url' => result.dig('signers', 0, 'sign_url'),
      'faltando' => faltando,
      'criado_em' => Time.zone.now.iso8601
    }
    # reload: a chamada HTTP demora e um snapshot velho reverteria gravações
    # paralelas em custom_attributes (colheita/AdvBox/painel).
    @lead.reload
    @lead.update!(custom_attributes: (@lead.custom_attributes || {}).merge('zapsign' => stored))
    stored
  end

  private

  def payload
    {
      template_id: TEMPLATE_ID,
      signer_name: nome,
      send_automatic_email: false,
      send_automatic_whatsapp: false,
      data: variaveis.map { |de, para| { de: de, para: para.presence || BLANK } }
    }
  end

  # As 12 variáveis do modelo. Endereço/estado civil/profissão vêm da extração
  # da colheita quando existem; o que faltar sai como linha em branco no doc
  # (lista em 'faltando' pro closer completar antes de colher a assinatura).
  def variaveis
    {
      '{{nome}}' => nome,
      '{{estado civil}}' => colheita_cliente['estado_civil'],
      '{{profissão}}' => colheita_cliente['profissao'],
      '{{CPF}}' => cpf_formatado,
      '{{rua}}' => endereco['rua'],
      '{{número}}' => endereco['numero'],
      '{{bairro}}' => endereco['bairro'],
      '{{cidade}}' => cidade,
      '{{UF}}' => uf,
      '{{email}}' => @contact&.email,
      '{{telefone}}' => telefone,
      '{{data de hoje}}' => data_de_hoje
    }
  end

  def faltando
    variaveis.select { |_de, para| para.blank? }.keys
  end

  def nome
    @contact&.name.presence || @lead.name
  end

  def colheita_cliente
    @lead.custom_attributes&.dig('colheita', 'dados', 'cliente') || {}
  end

  # A colheita traz o endereço numa string só; rua/número/bairro separados só
  # se um dia forem campos próprios — até lá a rua carrega o endereço inteiro.
  def endereco
    completo = colheita_cliente['endereco'].presence
    completo ? { 'rua' => completo, 'numero' => '', 'bairro' => '' } : {}
  end

  def cidade
    @contact&.additional_attributes&.dig('city').presence
  end

  def uf
    @contact&.additional_attributes&.dig('state').presence || (cidade ? 'SC' : nil)
  end

  def cpf_formatado
    digitos = @contact&.cpf.to_s
    return nil if digitos.length != 11

    "#{digitos[0..2]}.#{digitos[3..5]}.#{digitos[6..8]}-#{digitos[9..10]}"
  end

  def telefone
    @contact&.phone_number.to_s.delete('^0-9').delete_prefix('55').presence
  end

  def data_de_hoje
    hoje = Time.zone.today
    "#{hoje.day} de #{MESES[hoje.month - 1]} de #{hoje.year}"
  end
end
