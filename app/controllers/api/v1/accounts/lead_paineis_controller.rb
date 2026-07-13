# Painel de possibilidades (estilo Previdenciarista): todos os cartões de
# benefício do lead — pré-reforma e EC 103, elegível ou não, com "faltou" e
# previsão. Usa o CNIS anexado ao lead (quando houver) + vínculos manuais do
# advogado (ex.: atividade rural que não está no CNIS).
class Api::V1::Accounts::LeadPaineisController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def create
    authorize(@lead, :show?)
    return render json: { error: 'DER inválida — use o formato AAAA-MM-DD' }, status: :unprocessable_entity if der.blank?

    render json: Ramon::MotorClient.painel(motor_payload)
  rescue Ramon::MotorClient::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Ramon::MotorClient::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end

  def permitted
    params.permit(:nascimento, :sexo, :der, :memoria_calculo,
                  vinculos_extras: [:inicio, :fim, :tipo, :salario])
  end

  def der
    @der ||= data(permitted[:der])
  end

  def data(valor)
    Date.iso8601(valor.to_s)
  rescue ArgumentError
    nil
  end

  def cnis_entrada
    @cnis_entrada ||= @lead.cnis&.dig('entrada') || {}
  end

  def segurado
    cnis_entrada['segurado'].presence ||
      { nascimento: permitted[:nascimento], sexo: permitted[:sexo].presence || 'M' }
  end

  # Vínculos manuais: contam tempo/carência no motor; com salário informado
  # também entram na média (competências mensais geradas aqui).
  def extras
    @extras ||= (permitted[:vinculos_extras] || []).filter_map { |v| extra_de(v) }
  end

  def extra_de(vinculo)
    inicio = data(vinculo[:inicio])
    fim = data(vinculo[:fim])
    return if inicio.blank? || fim.blank? || fim < inicio

    { inicio: inicio, fim: fim, tipo: vinculo[:tipo].presence || 'EMPREGO',
      salario: vinculo[:salario] }
  end

  def competencias_de(extra)
    return [] if extra[:salario].blank?

    salario = format('%.2f', extra[:salario].to_f)
    mes = extra[:inicio].beginning_of_month
    lista = []
    while mes <= extra[:fim]
      lista << { ano: mes.year, mes: mes.month, salario: salario }
      mes = mes.next_month
    end
    lista
  end

  def motor_payload
    {
      segurado: segurado,
      der: der.iso8601,
      competencias: (cnis_entrada['competencias'] || []) + extras.flat_map { |e| competencias_de(e) },
      vinculos: (cnis_entrada['vinculos'] || []) + extras.map do |e|
        { inicio: e[:inicio].iso8601, fim: e[:fim].iso8601, tipo: e[:tipo], indicadores: [] }
      end,
      memoria_calculo: ActiveModel::Type::Boolean.new.cast(permitted[:memoria_calculo]) || false
    }
  end
end
