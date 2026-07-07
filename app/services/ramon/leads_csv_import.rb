require 'csv'

module Ramon
  # Import CSV de pessoas + casos (item 4c-22 / Base 10.000).
  # Template: nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
  # ponytail: linha a linha (sem bulk); ~10k linhas ok em job :low — activerecord-import se doer.
  class LeadsCsvImport
    CASE_COLUMNS = %w[beneficio tese etapa valor ganho_em].freeze

    def initialize(data_import)
      @data_import = data_import
      @account = data_import.account
      @rejected = []
      @processed = 0
      @total = 0
    end

    def perform
      @data_import.update!(status: :processing)
      csv_rows.each { |row| import_row(row) }
      finish!
    rescue CSV::MalformedCSVError => e
      @data_import.update!(status: :failed, processing_errors: e.message)
    end

    private

    def csv_rows
      CSV.parse(@data_import.import_file.download, headers: true)
    end

    def import_row(row)
      @total += 1
      attrs = row.to_h.transform_values { |v| v.to_s.strip.presence }
      ActiveRecord::Base.transaction do
        contact = upsert_contact(attrs)
        create_case(contact, attrs) if case_columns_present?(attrs)
      end
      @processed += 1
    rescue StandardError => e
      @rejected << (row.fields + [e.message])
    end

    def upsert_contact(attrs)
      cpf = attrs['cpf']&.gsub(/\D/, '').presence
      phone = normalize_phone(attrs['telefone'])
      contact = find_contact(cpf, phone, attrs['email'])
      contact ||= @account.contacts.new(name: attrs['nome'] || phone || cpf)
      fill_blank(contact, :cpf, cpf)
      fill_blank(contact, :phone_number, phone)
      fill_blank(contact, :email, attrs['email'])
      fill_blank(contact, :data_nascimento, parse_date(attrs['data_nascimento'], 'data_nascimento'))
      fill_blank(contact, :sexo, attrs['sexo']&.upcase)
      contact.save!
      contact
    end

    def find_contact(cpf, phone, email)
      (cpf && @account.contacts.find_by(cpf: cpf)) ||
        (phone && @account.contacts.find_by(phone_number: phone)) ||
        (email && @account.contacts.from_email(email)&.then { |c| c.account_id == @account.id ? c : nil })
    end

    def fill_blank(contact, attribute, value)
      contact[attribute] = value if value.present? && contact[attribute].blank?
    end

    def case_columns_present?(attrs)
      attrs.values_at(*CASE_COLUMNS).any?(&:present?)
    end

    def create_case(contact, attrs)
      benefit = find_by_name!(@account.benefit_types, attrs['beneficio'], 'beneficio')
      thesis = find_by_name!(@account.theses, attrs['tese'], 'tese')
      won_at = parse_date(attrs['ganho_em'], 'ganho_em')
      stage = target_stage(attrs['etapa'], won_at)
      return if duplicate_case?(contact, benefit, won_at)

      lead = @account.leads.create!(
        name: contact.name, contact_id: contact.id, lead_stage: stage,
        benefit_type: benefit, thesis: thesis,
        value: parse_decimal(attrs['valor']),
        source: attrs['origem'], channel: valid_channel(attrs['canal'])
      )
      lead.update!(won_at: won_at) if won_at.present?
    end

    def target_stage(etapa_name, won_at)
      return @account.lead_stages.find_by!(is_won: true) if won_at.present?
      return @account.lead_stages.order(:position).first if etapa_name.blank?

      @account.lead_stages.find_by('lower(name) = ?', etapa_name.downcase) ||
        raise("etapa desconhecida: #{etapa_name}")
    end

    def duplicate_case?(contact, benefit, won_at)
      scope = @account.leads.where(contact_id: contact.id, benefit_type: benefit)
      return scope.where(won_at: won_at.all_day).exists? if won_at.present?

      scope.open.exists?
    end

    def find_by_name!(relation, name, column)
      return nil if name.blank?

      relation.find_by('lower(name) = ?', name.downcase) || raise("#{column} desconhecido: #{name}")
    end

    def normalize_phone(raw)
      return nil if raw.blank?

      digits = raw.gsub(/\D/, '')
      return "+55#{digits}" if [10, 11].include?(digits.length)
      return "+#{digits}" if [12, 13].include?(digits.length) && digits.start_with?('55')

      raise "telefone inválido: #{raw}"
    end

    def parse_date(raw, column)
      return nil if raw.blank?

      Date.strptime(raw, '%d/%m/%Y')
    rescue Date::Error
      begin
        Date.iso8601(raw)
      rescue Date::Error
        raise "#{column} inválida: #{raw}"
      end
    end

    def parse_decimal(raw)
      return nil if raw.blank?

      raw.tr('.', '').tr(',', '.').to_d
    end

    def valid_channel(raw)
      Ramon::SourceCatalog::CHANNELS.any? { |c| c[:key] == raw } ? raw : nil
    end

    def finish!
      @data_import.update!(status: :completed, total_records: @total, processed_records: @processed)
      attach_failed_records
    end

    def attach_failed_records
      return if @rejected.empty?

      header = "nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem,erro\n"
      csv = header + @rejected.map(&:to_csv).join
      @data_import.failed_records.attach(
        io: StringIO.new(csv), filename: "rejeitadas_#{@data_import.id}.csv", content_type: 'text/csv'
      )
    end
  end
end
