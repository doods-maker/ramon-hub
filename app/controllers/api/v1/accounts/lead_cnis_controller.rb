# CNIS por caso (Onda 3b): recebe o PDF, manda o motor parsear e guarda o
# resultado no lead — o Simulador passa a usar o histórico real de salários.
class Api::V1::Accounts::LeadCnisController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def create
    authorize(@lead, :show?)
    return render json: { error: 'arquivo (PDF do CNIS) é obrigatório' }, status: :unprocessable_entity if params[:arquivo].blank?

    resultado = Ramon::MotorClient.cnis(params[:arquivo], sexo: params[:sexo].to_s)
    @lead.update!(cnis: stored(resultado))
    render json: @lead.cnis_resumo
  rescue Ramon::MotorClient::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Ramon::MotorClient::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  def destroy
    authorize(@lead, :show?)
    @lead.update!(cnis: nil)
    head :no_content
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end

  def stored(resultado)
    {
      entrada: resultado['entrada_calcular'],
      vinculos: resultado['vinculos'],
      avisos: avisos_de(resultado),
      filename: params[:arquivo].original_filename,
      uploaded_at: Time.current.iso8601
    }
  end

  def avisos_de(resultado)
    (resultado['avisos'] || []).map do |aviso|
      aviso['alvo'].present? ? "#{aviso['alvo']}: #{aviso['mensagem']}" : aviso['mensagem']
    end
  end
end
