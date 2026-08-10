# Planejamento de aposentadoria (fatia 3 do motor): cenários de contribuição
# projetados no tempo (regra a cumprir, RMI projetada, desembolso, payback).
# O hub é só proxy — nada é persistido no lead (cálculo efêmero, como
# elegibilidade/liquidação). PDF é a mesma conta em documento consultivo.
class Api::V1::Accounts::LeadPlanejamentosController < Api::V1::Accounts::BaseController
  include CalculoProxy
  include RegistraCalculo

  def create
    authorize(@lead, :show?)
    responder { render json: Ramon::MotorClient.planejamento(motor_payload) }
    registrar_calculo('planejamento')
  end

  def pdf
    authorize(@lead, :show?)
    responder do
      bytes = Ramon::MotorClient.planejamento_pdf(motor_payload.merge(segurado_nome: segurado_nome))
      send_data bytes, filename: "planejamento-lead-#{@lead.id}.pdf",
                       type: 'application/pdf', disposition: 'attachment'
    end
  end

  private

  def permitted
    params.permit(:data_calculo, :horizonte_anos, :segurado_nome,
                  cenarios: %i[nome salario aliquota])
  end

  def segurado_nome
    permitted[:segurado_nome].presence || @lead.contact&.name.to_s
  end

  # repassado cru pro motor — o motor valida forma/máximo (10 cenários).
  def cenarios
    (permitted[:cenarios] || []).map(&:to_h)
  end

  def motor_payload
    payload = {
      segurado: segurado_do_cnis_ou_contato,
      competencias: cnis_entrada['competencias'] || [],
      vinculos: cnis_entrada['vinculos'] || []
    }
    payload[:data_calculo] = permitted[:data_calculo] if permitted[:data_calculo].present?
    payload[:cenarios] = cenarios if cenarios.present?
    payload[:horizonte_anos] = permitted[:horizonte_anos] if permitted[:horizonte_anos].present?
    payload
  end
end
