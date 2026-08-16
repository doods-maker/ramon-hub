# Simulador ao vivo (Sala de Fechamento): chama o motor de cálculos e aplica a
# fórmula de honorário da tese do lead (percentual × atrasados + N × mensalidades).
class Api::V1::Accounts::LeadSimulacoesController < Api::V1::Accounts::BaseController
  include CalculoProxy
  include RegistraCalculo

  def create
    authorize(@lead, :show?)
    return render json: { error: 'DER inválida — use o formato AAAA-MM-DD' }, status: :unprocessable_entity if der.blank?

    responder do
      render json: simulacao(Ramon::MotorClient.incapacidade(motor_payload))
      registrar_calculo('honorario')
    end
  end

  private

  def permitted
    params.permit(:nascimento, :sexo, :der, :salario, :beneficio, :origem, :acrescimo_25, :usar_cnis, :memoria_calculo)
  end

  def usar_cnis?
    @usar_cnis ||= @lead.cnis.present? && ActiveModel::Type::Boolean.new.cast(permitted[:usar_cnis]) == true
  end

  def der
    @der ||= data(permitted[:der])
  end

  def motor_payload
    {
      segurado: segurado,
      der: der.iso8601,
      competencias: usar_cnis? ? @lead.cnis.dig('entrada', 'competencias') : competencias,
      beneficio: permitted[:beneficio],
      origem: permitted[:origem].presence || 'previdenciaria',
      acrescimo_25: ActiveModel::Type::Boolean.new.cast(permitted[:acrescimo_25]) || false,
      # relatório competência-a-competência do motor (opt-in — payload grande)
      memoria_calculo: ActiveModel::Type::Boolean.new.cast(permitted[:memoria_calculo]) || false
    }
  end

  # Com CNIS anexado ao caso (Onda 3b), o histórico real substitui a estimativa.
  def segurado
    return @lead.cnis.dig('entrada', 'segurado') if usar_cnis?

    { nascimento: permitted[:nascimento], sexo: permitted[:sexo] }
  end

  # ponytail: salário médio repetido nas 12 competências anteriores à DER —
  # bom o bastante pra estimativa de conversa; histórico real virá do upload de CNIS.
  def competencias
    salario = format('%.2f', permitted[:salario].to_f)
    (1..12).map do |n|
      mes = der << (13 - n)
      { ano: mes.year, mes: mes.month, salario: salario }
    end
  end

  def simulacao(resultado)
    mensal = decimal(resultado['valor_hoje']) || decimal(resultado['rmi']) || BigDecimal(0)
    meses = meses_desde_der
    atrasados = mensal * meses
    {
      mensal: money(mensal),
      perda_mensal: money(mensal),
      atrasados: money(atrasados),
      atrasados_estimativa: {
        estimado: true,
        meses: meses,
        base: 'mensal (a valores de hoje) × meses entre a DER e hoje'
      },
      honorario: honorario(atrasados, mensal),
      avisos: resultado['avisos'] || [],
      motor: resultado.except('avisos')
    }
  end

  def honorario(atrasados, mensal)
    Ramon::Honorario.calcular(@lead.thesis, atrasados: atrasados, mensal: mensal)
  end

  def meses_desde_der
    hoje = Date.current
    [((hoje.year - der.year) * 12) + (hoje.month - der.month), 0].max
  end

  def money(valor)
    format('%.2f', valor)
  end
end
