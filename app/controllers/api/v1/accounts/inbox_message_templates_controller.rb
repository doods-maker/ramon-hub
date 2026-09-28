# Cria modelos de mensagem (templates) do WhatsApp Cloud pela tela da caixa.
# A listagem já vem no JSON da caixa (message_templates sincronizados).
class Api::V1::Accounts::InboxMessageTemplatesController < Api::V1::Accounts::BaseController
  CATEGORIES = %w[UTILITY MARKETING].freeze

  before_action :fetch_inbox

  def create
    return render json: { error: 'Invalid category' }, status: :unprocessable_entity unless CATEGORIES.include?(template_params[:category])

    response = @inbox.channel.provider_service.create_message_template(template_payload)
    return render json: { error: meta_error(response) }, status: :unprocessable_entity unless response.success?

    sync_templates
    render json: { id: response['id'], status: response['status'] }, status: :created
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :update?
    return if @inbox.whatsapp? && @inbox.channel.provider == 'whatsapp_cloud'

    render json: { error: 'Message templates are only available for WhatsApp Cloud inboxes' }, status: :bad_request
  end

  def template_params
    @template_params ||= params.require(:template).permit(:name, :category, :language, :body, examples: [])
  end

  def template_payload
    body = { type: 'BODY', text: template_params[:body] }
    body[:example] = { body_text: [template_params[:examples]] } if template_params[:examples].present?
    { name: template_params[:name], category: template_params[:category], language: template_params[:language], components: [body] }
  end

  def meta_error(response)
    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] || {} : {}
    error['error_user_msg'] || error['message'] || 'Template creation failed'
  end

  # O modelo já foi criado na Meta; falha ao ressincronizar não pode virar erro.
  def sync_templates
    @inbox.channel.sync_templates
  rescue StandardError => e
    Rails.logger.warn("Template sync after creation failed: #{e.message}")
  end
end
