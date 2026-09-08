# Tela "Painel do cliente" do hub: convidar cliente do ADVBOX, recado por
# processo, enviar documento pra assinatura. Convite é sempre clique humano.
class Api::V1::Accounts::PortalClientesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_cliente, only: [:show, :update, :convidar, :assinatura]
  before_action :check_authorization

  def index
    render json: { payload: Current.account.portal_clientes.order(:nome).map { |c| linha(c) } }
  end

  def show
    render json: detalhe(@cliente)
  end

  def create
    cliente = Current.account.portal_clientes.create!(params.permit(:advbox_customer_id, :nome, :cpf, :email))
    sincronizar(cliente)
    convidar!(cliente)
    render json: linha(cliente)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    @cliente.update!(recados: params[:recados].to_unsafe_h.transform_values(&:to_s).compact_blank) if params.key?(:recados)
    @cliente.update!(email: params[:email]) if params[:email].present?
    render json: detalhe(@cliente)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def convidar
    convidar!(@cliente)
    render json: linha(@cliente)
  end

  # PR 6
  def assinatura = head(:not_found)

  private

  def fetch_cliente
    @cliente = Current.account.portal_clientes.find(params[:id])
  end

  def check_authorization
    authorize(:portal_cliente, :"#{action_name}?")
  end

  def sincronizar(cliente)
    Ramon::PortalSyncService.new(cliente).perform
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError => e
    Rails.logger.warn("[PortalClientes] sync falhou cliente=#{cliente.id}: #{e.message}")
  end

  def convidar!(cliente)
    Ramon::PortalMailer.with(account: Current.account, cliente: cliente).convite.deliver_later
    cliente.update!(convidado_em: Time.current)
  end

  def linha(cliente)
    {
      id: cliente.id, nome: cliente.nome, cpf: cliente.cpf, email: cliente.email, advbox_customer_id: cliente.advbox_customer_id,
      convidado_em: cliente.convidado_em&.iso8601, termos_aceitos_em: cliente.termos_aceitos_em&.iso8601,
      sincronizado_em: cliente.sincronizado_em&.iso8601,
      processos: cliente.processos.map { |p| p.slice('id', 'numero', 'tipo', 'etapa', 'fase', 'docs_pendentes') },
      envios_count: cliente.envios.count, assinaturas_pendentes: cliente.assinaturas.pendentes.count
    }
  end

  def detalhe(cliente)
    linha(cliente).merge(
      recados: cliente.recados,
      envios: cliente.envios.order(created_at: :desc).map do |e|
        { id: e.id, item: e.item, lawsuit_id: e.lawsuit_id, drive_file_id: e.drive_file_id, advbox_post_id: e.advbox_post_id,
          created_at: e.created_at.iso8601 }
      end,
      assinaturas: cliente.assinaturas.order(created_at: :desc).map do |a|
        { id: a.id, nome: a.nome, status: a.status, assinado_em: a.assinado_em&.iso8601, created_at: a.created_at.iso8601 }
      end
    )
  end
end
