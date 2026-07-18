# Liquidação de sentença previdenciária (F3 do motor): parcelas devidas +
# atualização monetária + honorários. O hub é só proxy validador — o cálculo é
# do motor; nada é persistido no lead (cálculo efêmero, como a simulação).
# Obrigatórios/formato são validados AQUI (mensagem pt) porque erro de forma no
# motor (pydantic) volta como lista em inglês; os 422 de domínio do motor
# (datas fora de ordem, DIB < 2010) já vêm em pt e passam direto.
class Api::V1::Accounts::LeadLiquidacoesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  DATAS_OPCIONAIS = %i[data_citacao data_ajuizamento data_sentenca_ou_acordao data_fim data_calculo].freeze
  REGIMES = %w[art406 selic].freeze

  def create
    authorize(@lead, :show?)
    erro = erro_de_validacao
    return render json: { error: erro }, status: :unprocessable_entity if erro

    responder { render json: Ramon::MotorClient.liquidacao(motor_payload) }
  end

  def pdf
    authorize(@lead, :show?)
    erro = erro_de_validacao
    return render json: { error: erro }, status: :unprocessable_entity if erro

    responder do
      bytes = Ramon::MotorClient.liquidacao_pdf(motor_payload.merge(cabecalho))
      send_data bytes, filename: "liquidacao-lead-#{@lead.id}.pdf",
                       type: 'application/pdf', disposition: 'attachment'
    end
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end

  def permitted
    params.permit(:rmi, :dib, :no_piso, :data_citacao, :data_ajuizamento, :data_sentenca_ou_acordao,
                  :data_fim, :data_calculo, :honorarios_sucumbenciais_pct, :honorarios_contratuais_pct,
                  :regime_pos_ec136, :segurado_nome, :numero_processo, :numero_beneficio,
                  abatimentos: [:ano, :mes, :valor])
  end

  def responder
    yield
  rescue Ramon::MotorClient::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Ramon::MotorClient::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  def erro_de_validacao
    return 'RMI obrigatória — informe um número maior que zero' if rmi.nil? || rmi <= 0
    return 'DIB inválida — use o formato AAAA-MM-DD' if data(permitted[:dib]).nil?

    erro_datas_opcionais || erro_percentuais || erro_regime || erro_abatimentos
  end

  def erro_datas_opcionais
    DATAS_OPCIONAIS.each do |campo|
      valor = permitted[campo]
      return "#{campo} inválida — use o formato AAAA-MM-DD" if valor.present? && data(valor).nil?
    end
    nil
  end

  def erro_percentuais
    %i[honorarios_sucumbenciais_pct honorarios_contratuais_pct].each do |campo|
      valor = permitted[campo]
      next if valor.blank?

      pct = decimal(valor)
      return 'honorários em % inválidos — use um número entre 0 e 100' if pct.nil? || pct <= 0 || pct > 100
    end
    nil
  end

  def erro_regime
    regime = permitted[:regime_pos_ec136]
    return if regime.blank? || REGIMES.include?(regime)

    'regime_pos_ec136 inválido — use art406 ou selic'
  end

  def erro_abatimentos
    abatimentos.each do |a|
      valor = decimal(a[:valor])
      return 'abatimento inválido — informe ano, mês e valor maior que zero' if a[:ano].blank? || a[:mes].blank? || valor.nil? || valor <= 0
    end
    nil
  end

  def abatimentos
    permitted[:abatimentos] || []
  end

  def motor_payload
    payload = {
      rmi: format('%.2f', rmi),
      dib: permitted[:dib],
      no_piso: ActiveModel::Type::Boolean.new.cast(permitted[:no_piso]) || false,
      regime_pos_ec136: permitted[:regime_pos_ec136].presence || 'art406',
      abatimentos: abatimentos.map { |a| { ano: a[:ano].to_i, mes: a[:mes].to_i, valor: format('%.2f', decimal(a[:valor])) } }
    }
    DATAS_OPCIONAIS.each { |campo| payload[campo] = permitted[campo] if permitted[campo].present? }
    %i[honorarios_sucumbenciais_pct honorarios_contratuais_pct].each do |campo|
      payload[campo] = permitted[campo].to_s if permitted[campo].present?
    end
    payload
  end

  def cabecalho
    { segurado_nome: permitted[:segurado_nome].to_s,
      numero_processo: permitted[:numero_processo].to_s,
      numero_beneficio: permitted[:numero_beneficio].to_s }
  end

  def rmi
    @rmi ||= decimal(permitted[:rmi])
  end

  def data(valor)
    Date.iso8601(valor.to_s)
  rescue ArgumentError
    nil
  end

  def decimal(valor)
    return if valor.blank?

    BigDecimal(valor.to_s)
  rescue ArgumentError
    nil
  end
end
