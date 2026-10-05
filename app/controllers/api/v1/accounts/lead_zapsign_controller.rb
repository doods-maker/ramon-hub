# Item 21 (fluxo A): botão "Gerar contrato" no painel do lead → ZapSign cria
# contrato + procuração pré-preenchidos e devolve o link de assinatura.
class Api::V1::Accounts::LeadZapsignController < Api::V1::Accounts::BaseController
  before_action :fetch_lead, only: [:create, :preview, :dados]

  def create
    authorize(@lead, :show?)
    render json: Ramon::ZapsignContractService.new(@lead, template_id: params[:template_id]).perform
  rescue Ramon::ZapsignClient::RequestError => e
    render json: { error: e.body.to_s.truncate(300) }, status: :unprocessable_entity
  rescue Ramon::ZapsignClient::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  # O que sairia em branco no contrato + dados atuais do formulário (sem ZapSign).
  def preview
    authorize(@lead, :show?)
    render json: Ramon::ZapsignContractService.new(@lead).preview
  end

  # "Dados do contrato" do painel: grava no CONTATO (vale pros próximos casos
  # dele) e devolve a prévia nova.
  def dados
    authorize(@lead, :show?)
    contact = @lead.contact
    contact.custom_attributes = (contact.custom_attributes || {}).merge(dados_params.except('email'))
    contact.email = dados_params['email'].presence if dados_params.key?('email')
    contact.save!
    render json: Ramon::ZapsignContractService.new(@lead.reload).preview
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  # Modelos da conta ZapSign pro seletor do painel.
  def templates
    authorize(:lead, :index?)
    render json: Ramon::ZapsignClient.templates
  rescue Ramon::ZapsignClient::UnavailableError, Ramon::ZapsignClient::RequestError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  # CEP → rua/bairro/cidade/UF pelo ViaCEP, chamado do servidor (o navegador
  # não fala com terceiros). 404 = CEP inexistente; 503 = ViaCEP fora do ar.
  def cep
    authorize(:lead, :index?)
    digitos = params[:cep].to_s.delete('^0-9')
    return head :not_found unless digitos.length == 8

    body = HTTParty.get("https://viacep.com.br/ws/#{digitos}/json/", open_timeout: 3, read_timeout: 5).parsed_response
    return head :not_found if !body.is_a?(Hash) || body['erro']

    render json: { cep: digitos, rua: body['logradouro'], bairro: body['bairro'], cidade: body['localidade'], uf: body['uf'] }
  rescue Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, EOFError
    head :service_unavailable
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end

  def dados_params
    @dados_params ||= params.permit(:estado_civil, :profissao, :email,
                                    endereco: [:cep, :rua, :numero, :complemento, :bairro, :cidade, :uf]).to_h
  end
end
