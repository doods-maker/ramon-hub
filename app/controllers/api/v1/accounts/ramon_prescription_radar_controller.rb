class Api::V1::Accounts::RamonPrescriptionRadarController < Api::V1::Accounts::BaseController
  LIST_LIMIT = 100

  before_action :current_account
  before_action :check_authorization

  def show
    rows = radar_rows
    @summary = summary(rows)
    @items = rows.first(LIST_LIMIT)
  end

  private

  # Mesmas permissões do Centro de Comando (admin + agent).
  def check_authorization
    authorize(:ramon_dashboard, :show?)
  end

  # Toda a base do funil com DCB conhecida — abertos E perdidos (o prazo do
  # lead perdido continua correndo); ganhos ficam de fora.
  def leads_with_dcb
    Current.account.leads.funil
           .where.not(dcb_em: nil)
           .joins(:lead_stage).where(lead_stages: { is_won: false })
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
    info = lead.prescription
    {
      lead_id: lead.id,
      name: lead.name,
      benefit_type_name: lead.benefit_type&.name,
      dcb_em: lead.dcb_em,
      stage_name: lead.lead_stage.name,
      is_lost: lead.lead_stage.is_lost,
      monthly_value: lead.benefit_monthly_value&.to_f,
      months_since_dcb: info[:months_since_dcb],
      lost_installments: info[:lost_installments],
      lost_value: info[:lost_value]&.to_f,
      months_to_cliff: [Lead::PRESCRIPTION_WINDOW_MONTHS - info[:months_since_dcb], 0].max,
      pct_consumed: [info[:months_since_dcb].fdiv(Lead::PRESCRIPTION_WINDOW_MONTHS), 1.0].min,
      # Mesmo critério do guard LGPD do envio em massa (Whatsapp::OneoffCampaignService).
      consent_marketing: lead.contact&.custom_attributes&.dig('consent_marketing', 'granted') == true
    }
  end

  # Sangrando = já perde parcelas; em risco 90d = cliff em até 3 meses (e ainda não sangra).
  def summary(rows)
    bleeding = rows.select { |row| row[:lost_installments].positive? }
    at_risk = rows.select { |row| row[:lost_installments].zero? && row[:months_to_cliff] <= 3 }
    {
      bleeding_monthly: bleeding.sum { |row| row[:monthly_value] || 0.0 },
      bleeding_count: bleeding.size,
      at_risk_90d_monthly: at_risk.sum { |row| row[:monthly_value] || 0.0 },
      at_risk_90d_count: at_risk.size
    }
  end
end
