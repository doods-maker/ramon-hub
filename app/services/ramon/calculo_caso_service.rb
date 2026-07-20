# Caso de cálculo (tela Cálculos): resolve a pessoa (cadastro AdvBox ou contato
# do hub) e garante um lead pra pendurar CNIS/simulações. Se a pessoa já tem
# lead — comercial ou não — o cálculo vive nele; senão nasce um caso oculto
# (source calculo-advbox, fora do funil — ver Lead.funil).
class Ramon::CalculoCasoService
  def initialize(account:, params:)
    @account = account
    @params = params.to_h.symbolize_keys
  end

  def perform
    contact = resolve_contact
    leads = @account.leads.where(contact_id: contact.id).to_a
    leads = [criar_caso(contact)] if leads.empty?
    { contact: contact, leads: leads }
  end

  private

  def resolve_contact
    return @account.contacts.find(@params[:contact_id]) if @params[:contact_id].present?

    contact = find_by_cpf || find_by_phone
    contact ? fill_blanks(contact) : create_contact
  end

  def cpf_digits
    @cpf_digits ||= @params[:cpf].to_s.gsub(/\D/, '').presence
  end

  def phone_e164
    digits = @params[:telefone].to_s.gsub(/\D/, '')
    digits = "55#{digits}" if [10, 11].include?(digits.length)
    return unless [12, 13].include?(digits.length) && digits.start_with?('55')

    "+#{digits}"
  end

  def find_by_cpf
    cpf_digits && @account.contacts.find_by(cpf: cpf_digits)
  end

  def find_by_phone
    phone_e164 && @account.contacts.find_by(phone_number: phone_e164)
  end

  def nascimento
    Date.iso8601(@params[:nascimento].to_s)
  rescue Date::Error
    nil
  end

  # Dado humano nunca é sobrescrito (padrão fill_contact_blanks da colheita).
  def fill_blanks(contact)
    updates = {}
    updates[:cpf] = cpf_digits if contact.cpf.blank? && cpf_digits
    updates[:data_nascimento] = nascimento if contact.data_nascimento.blank? && nascimento
    save_tolerando_cpf(contact, updates)
    contact
  end

  def create_contact
    contact = @account.contacts.new(
      name: @params[:nome].to_s.strip.presence || 'Sem nome',
      cpf: cpf_digits, phone_number: phone_e164,
      email: @params[:email].presence, data_nascimento: nascimento
    )
    return contact if contact.save

    # CPF inválido/duplicado não derruba o fluxo: tenta sem ele.
    contact.cpf = nil
    contact.save!
    contact
  end

  def save_tolerando_cpf(contact, updates)
    return if updates.empty? || contact.update(updates)

    updates.delete(:cpf)
    contact.reload.update(updates) if updates.any?
  end

  def criar_caso(contact)
    @account.leads.create!(
      contact: contact,
      lead_stage: @account.lead_stages.order(:position).first,
      name: contact.name,
      source: Lead::FONTE_CALCULO
    )
  end
end
