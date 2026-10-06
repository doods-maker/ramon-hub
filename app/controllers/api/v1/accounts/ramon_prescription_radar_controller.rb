class Api::V1::Accounts::RamonPrescriptionRadarController < Api::V1::Accounts::BaseController
  LIST_LIMIT = 100
  RESGATE_LABEL = 'resgate-prescricao'.freeze

  before_action :current_account
  before_action :check_authorization

  def show
    rows = radar_rows
    @summary = summary(rows)
    @items = rows.first(LIST_LIMIT)
  end

  # Campanha de resgate (só gestor): etiqueta os contatos com WhatsApp de TODOS
  # os leads do radar (não só os 100 da lista). Consentimento vem do contrato/
  # procuração (regra do escritório) — sem filtrar pela flag do hub. Nada é
  # criado nem enviado aqui: a campanha quem monta e envia é o gestor.
  def resgate
    Current.account.labels.find_or_create_by!(title: RESGATE_LABEL)
    contatos = contatos_com_whatsapp(radar_rows)
    contatos.each { |contact| contact.add_labels([RESGATE_LABEL]) }
    render json: { label: RESGATE_LABEL, count: contatos.size }
  end

  private

  def check_authorization
    authorize(:ramon_prescription_radar, :"#{action_name}?")
  end

  def contatos_com_whatsapp(rows)
    Current.account.contacts.where(id: rows.filter_map { |row| row[:contact_id] if row[:has_whatsapp] })
  end

  # Toda a base do funil com DCB conhecida — abertos E perdidos (o prazo do
  # lead perdido continua correndo) e clientes ainda juntando documentos (o
  # prazo corre até o protocolo); ganho com docs completos fica de fora.
  def leads_with_dcb
    Current.account.leads.funil
           .where.not(dcb_em: nil)
           .joins(:lead_stage).where('lead_stages.is_won = FALSE OR leads.docs_completos_em IS NULL')
           .includes(:lead_stage, :benefit_type, :contact)
  end

  # ponytail: cálculo em memória sobre a base com DCB (centenas de leads);
  # mover pra SQL se a base crescer a ponto de doer.
  def radar_rows
    leads_with_dcb.map { |lead| row_for(lead) }
                  .select { |row| row[:lost_installments].positive? || row[:pct_consumed] > 0.5 }
                  .sort_by { |row| [-(row[:lost_value] || 0.0), -row[:pct_consumed]] }
  end

  def row_for(lead)
    {
      lead_id: lead.id,
      name: lead.name,
      benefit_type_name: lead.benefit_type&.name,
      dcb_em: lead.dcb_em,
      stage_name: lead.lead_stage.name,
      is_lost: lead.lead_stage.is_lost,
      is_client: lead.lead_stage.is_won,
      monthly_value: lead.benefit_monthly_value&.to_f,
      contact_id: lead.contact_id,
      has_whatsapp: lead.contact&.phone_number.present? || false
    }.merge(prazo(lead.prescription))
  end

  def prazo(info)
    {
      months_since_dcb: info[:months_since_dcb],
      lost_installments: info[:lost_installments],
      lost_value: info[:lost_value]&.to_f,
      months_to_cliff: [Lead::PRESCRIPTION_WINDOW_MONTHS - info[:months_since_dcb], 0].max,
      pct_consumed: [info[:months_since_dcb].fdiv(Lead::PRESCRIPTION_WINDOW_MONTHS), 1.0].min
    }
  end

  # Sangrando = já perde parcelas; em risco 90d = cliff em até 3 meses (e ainda não sangra).
  def summary(rows)
    bleeding = rows.select { |row| row[:lost_installments].positive? }
    at_risk = rows.select { |row| row[:lost_installments].zero? && row[:months_to_cliff] <= 3 }
    {
      bleeding_monthly: monthly_sum(bleeding),
      bleeding_count: bleeding.size,
      at_risk_90d_monthly: monthly_sum(at_risk),
      at_risk_90d_count: at_risk.size,
      total_count: rows.size,
      # contatos (distintos) que a campanha de resgate etiqueta
      rescue_count: rows.filter_map { |row| row[:contact_id] if row[:has_whatsapp] }.uniq.size
    }
  end

  def monthly_sum(rows)
    rows.sum { |row| row[:monthly_value] || 0.0 }
  end
end
