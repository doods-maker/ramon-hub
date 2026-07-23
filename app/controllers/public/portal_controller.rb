# Portal do cliente (mock 4a): página pública server-rendered com link mágico
# por lead. Sem senha — o token urlsafe de 24 bytes É a credencial. Herda de
# ActionController::Base direto (não do PublicController, que desliga CSRF e
# responde JSON) — aqui o form de upload usa a proteção CSRF padrão do Rails.
class Public::PortalController < ActionController::Base
  include ::FileTypeHelper

  layout 'ramon_portal'

  MAX_UPLOAD_BYTES = 10.megabytes
  ALLOWED_CONTENT_TYPES = %w[application/pdf image/jpeg image/jpg image/png image/heic image/heif].freeze

  before_action :fetch_lead

  def show
    @stages = open_stages
    @current_index = @lead.won_at.present? || @lead.lost_at.present? ? nil : @stages.index(@lead.lead_stage)
    @docs_missing = docs_missing
  end

  def upload
    return redirect_invalid_file unless valid_upload?
    return redirect_to ramon_portal_path(@lead.portal_token) if @lead.conversation.blank?

    create_incoming_message!
    redirect_to ramon_portal_path(@lead.portal_token), flash: { portal_notice: 'Recebemos seu documento. Obrigado!' }
  end

  private

  def fetch_lead
    token = params[:token].to_s
    # token vazio JAMAIS pode virar find_by(portal_token: nil) — casaria um lead sem token
    @lead = token.present? ? Lead.find_by(portal_token: token) : nil
    render :invalid, status: :not_found if @lead.nil?
  end

  # Etapas abertas do funil, na ordem do Kanban — a timeline do cliente.
  def open_stages
    @lead.account.lead_stages.where(is_won: false, is_lost: false).to_a
  end

  def docs_missing
    return [] if @lead.thesis.blank?

    status_map = @lead.custom_attributes&.dig('doc_status') || {}
    @lead.thesis.thesis_items.where(section: 'documento').filter_map do |item|
      status = status_map[item.id.to_s].presence || 'pendente'
      next if status == 'recebido'

      item.title.presence || item.content
    end
  end

  def valid_upload?
    file = params[:file]
    file.respond_to?(:content_type) &&
      ALLOWED_CONTENT_TYPES.include?(file.content_type.to_s.downcase) &&
      file.size.to_i.positive? && file.size <= MAX_UPLOAD_BYTES
  end

  def redirect_invalid_file
    redirect_to ramon_portal_path(@lead.portal_token),
                flash: { portal_alert: 'Não foi possível receber o arquivo — envie um PDF ou foto (JPG/PNG/HEIC) de até 10 MB.' }
  end

  def create_incoming_message!
    conversation = @lead.conversation
    message = conversation.messages.build(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :incoming,
      sender: conversation.contact,
      content: 'Documento enviado pelo portal do cliente'
    )
    message.attachments.build(account_id: conversation.account_id, file: params[:file],
                              file_type: file_type(params[:file].content_type))
    message.save!
  end
end
