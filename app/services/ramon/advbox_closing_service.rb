# Item 21 (metade AdvBox): lead marcado como GANHO no hub → cliente + caso +
# tarefa criados no AdvBox via API, com os mesmos dados do lead. A metade
# ZapSign entra quando houver conta/modelos (gate do Eduardo).
class Ramon::AdvboxClosingService
  # IDs da conta AdvBox da banca (GET /settings; escolhas do Eduardo 15/07/2026).
  # ponytail: fork single-tenant — IDs em constantes; virar config se um dia houver 2ª conta.
  USERS_ID = 266_778     # Eduardo Schlata
  STAGE_ID = 3_736_299   # CONTRATO FECHADO (Marketing)
  TASK_ID = 8_745_394    # 1º CONTATO COM O LEAD

  # Tese do hub → tipo de processo no AdvBox. Fora do mapa cai no default (a
  # tese-foco) com aviso [CONFERIR tipo] nas notas do caso.
  TYPE_BY_THESIS = {
    /auxílio-acidente/i => 2_408_556,        # AUXÍLIO-ACIDENTE - COMUM (B36)
    /temporária|auxílio-doença/i => 2_351_928, # AUXÍLIO-DOENÇA - COMUM (B31)
    /permanente|invalidez/i => 2_351_777     # APOSENTADORIA POR INVALIDEZ (B32)
  }.freeze
  TYPE_DEFAULT = 2_408_556

  # source/channel do lead → origem no AdvBox (fallback = ANÚNCIO, de onde vem
  # o grosso da captação).
  ORIGINS = {
    /instagram/i => 596_178, /facebook|meta/i => 596_176, /google/i => 596_177,
    /indica/i => 596_179, /\blp\b|site|landing/i => 596_180
  }.freeze
  ORIGIN_DEFAULT = 596_175 # ANÚNCIO

  def initialize(lead)
    @lead = lead
    @contact = lead.contact
  end

  def perform
    return if @lead.won_at.blank? || synced?

    customer_id = find_or_create_customer
    lawsuit_id = Ramon::AdvboxClient.create_lawsuit(lawsuit_payload(customer_id))['lawsuits_id']
    post_id = Ramon::AdvboxClient.create_post(post_payload(lawsuit_id))['posts_id']
    write_back(customer_id, lawsuit_id, post_id)
  rescue Ramon::AdvboxClient::UnavailableError
    raise # retry no job (rede/5xx)
  rescue StandardError => e
    mark_error(e)
  end

  private

  def synced?
    @lead.custom_attributes&.dig('advbox', 'lawsuits_id').present?
  end

  # 422 de CPF duplicado não traz o id — buscar por identification resolve.
  def find_or_create_customer
    Ramon::AdvboxClient.create_customer(customer_payload)['customers_id']
  rescue Ramon::AdvboxClient::RequestError => e
    raise unless e.duplicate? && cpf.present?

    existing = customer_list(Ramon::AdvboxClient.customers(identification: cpf)).first
    raise e if existing.blank?

    existing['id']
  end

  def customer_list(response)
    return response if response.is_a?(Array)

    response.is_a?(Hash) ? Array(response['data']) : []
  end

  def cpf
    @contact&.cpf.presence
  end

  def customer_payload
    {
      users_id: USERS_ID,
      customers_origins_id: origin_id,
      name: @contact&.name.presence || @lead.name,
      identification: cpf,
      cellphone: @contact&.phone_number&.delete('^0-9'),
      birthdate: @contact&.data_nascimento&.iso8601,
      notes: "Lead ##{@lead.id} do ramon-hub · tese: #{@lead.thesis&.name || '—'}"
    }.compact
  end

  def lawsuit_payload(customer_id)
    {
      users_id: USERS_ID,
      customers_id: [customer_id],
      stages_id: STAGE_ID,
      type_lawsuits_id: type_id,
      date: Time.zone.today.iso8601,
      fees_expec: @lead.value&.to_f,
      notes: lawsuit_notes
    }.compact
  end

  def post_payload(lawsuit_id)
    {
      from: USERS_ID.to_s,
      guests: [USERS_ID],
      tasks_id: TASK_ID.to_s,
      lawsuits_id: lawsuit_id.to_s,
      start_date: Time.zone.today.iso8601,
      comments: "Fechado no hub — fazer o 1º contato do jurídico (lead ##{@lead.id})."
    }
  end

  def type_id
    thesis_name = @lead.thesis&.name
    return TYPE_DEFAULT if thesis_name.blank?

    TYPE_BY_THESIS.find { |pattern, _| thesis_name.match?(pattern) }&.last || TYPE_DEFAULT
  end

  def type_mapped?
    @lead.thesis&.name.present? && TYPE_BY_THESIS.any? { |pattern, _| @lead.thesis.name.match?(pattern) }
  end

  # Plano B do upload (a API não sobe documentos): link da conversa nas notas.
  def lawsuit_notes
    parts = ["Caso criado automaticamente pelo ramon-hub no fechamento do lead ##{@lead.id}."]
    parts << '[CONFERIR tipo de processo — tese fora do mapa automático]' unless type_mapped?
    if @lead.conversation
      parts << "Conversa/dossiê: #{ENV.fetch('FRONTEND_URL', '')}/app/accounts/#{@lead.account_id}/conversations/#{@lead.conversation.display_id}"
    end
    parts.join("\n")
  end

  def origin_id
    haystack = "#{@lead.source} #{@lead.channel}"
    ORIGINS.find { |pattern, _| haystack.match?(pattern) }&.last || ORIGIN_DEFAULT
  end

  def write_back(customer_id, lawsuit_id, post_id)
    merge_advbox('customers_id' => customer_id, 'lawsuits_id' => lawsuit_id,
                 'posts_id' => post_id, 'sincronizado_em' => Time.zone.now.iso8601)
  end

  def mark_error(error)
    Rails.logger.error("AdvboxClosing: falha no lead #{@lead.id}: #{error.message}")
    merge_advbox('erro' => error.message.truncate(300), 'em' => Time.zone.now.iso8601)
  end

  def merge_advbox(payload)
    @lead.update!(custom_attributes: (@lead.custom_attributes || {}).merge('advbox' => payload))
  end
end
