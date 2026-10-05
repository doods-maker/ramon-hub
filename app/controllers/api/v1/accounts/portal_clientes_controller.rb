# Tela "Painel do cliente" do hub: convidar cliente do ADVBOX (gera a senha
# provisória), recado por processo, enviar documento pra assinatura. Convite é
# sempre clique humano.
class Api::V1::Accounts::PortalClientesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_cliente, except: [:index, :create]
  before_action :check_authorization

  def index
    clientes = Current.account.portal_clientes.order(:nome).to_a
    render json: { payload: clientes.map { |c| portal_json.linha(c) }, metricas: portal_json.metricas(clientes),
                   email_configurado: Ramon::PortalConvite.email_configurado?, permissoes: permissoes }
  end

  def show
    render json: portal_json.detalhe(@cliente)
  end

  # Convidar de novo o mesmo cliente do ADVBOX ATUALIZA a linha (nome/CPF/e-mail
  # corrigidos lá) em vez de 422 por customer_id duplicado — é o único jeito de
  # consertar uma conta que ficou sem CPF (linhas anteriores ao login por CPF).
  def create
    cliente = Current.account.portal_clientes.find_or_initialize_by(advbox_customer_id: params[:advbox_customer_id])
    authorize(:portal_cliente, :nova_senha?) if cliente.convidado_em.present?
    cliente.update!(params.permit(:nome, :cpf, :email, :telefone))
    sincronizar(cliente)
    render json: entregar_senha(cliente)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    salvar_recados if params.key?(:recados)
    salvar_email if params.key?(:email)
    render json: portal_json.detalhe(@cliente)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  # Excluir = a conta some (envios/assinaturas junto); o cliente do ADVBOX fica.
  def destroy
    registrar('excluiu', "#{@cliente.nome} (CPF #{@cliente.cpf})")
    @cliente.destroy!
    head :no_content
  end

  # Reenviar convite = gerar senha provisória nova (a anterior deixa de valer).
  # 1º convite: qualquer agente. Senha nova de quem já tem acesso: nova_senha?.
  def convidar
    authorize(:portal_cliente, :nova_senha?) if @cliente.convidado_em.present?
    render json: entregar_senha(@cliente)
  end

  # Suspender: não entra e cai das sessões abertas; nada é apagado.
  def suspender
    @cliente.suspender!
    registrar('suspendeu')
    render json: portal_json.linha(@cliente)
  end

  def reativar
    @cliente.reativar!
    registrar('reativou')
    render json: portal_json.linha(@cliente)
  end

  def assinatura
    a = criar_assinatura!
    registrar('enviou_assinatura', a.nome)
    render json: { id: a.id, nome: a.nome, status: a.status }
  rescue Ramon::ZapsignClient::UnavailableError, Ramon::ZapsignClient::RequestError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  private

  def portal_json = Ramon::PortalClienteJson

  # Trilha de auditoria (PortalEvento): quem fez o quê neste cliente.
  def registrar(acao, detalhe = nil, cliente = @cliente)
    PortalEvento.create!(portal_cliente_id: cliente.id, user: Current.user, acao: acao, detalhe: detalhe)
  end

  def criar_assinatura!
    variaveis = params.fetch(:variaveis, {})
    variaveis = variaveis.respond_to?(:to_unsafe_h) ? variaveis.to_unsafe_h : variaveis.to_h
    doc = Ramon::ZapsignClient.create_doc_from_template(payload_assinatura(variaveis))
    signer = doc.dig('signers', 0, 'token')
    Ramon::ZapsignClient.update_signer(signer, auth_mode: 'assinaturaTela') if signer.present?
    @cliente.assinaturas.create!(doc_token: doc['token'], signer_token: signer, nome: params[:nome].presence || 'Documento')
  end

  def payload_assinatura(variaveis)
    {
      template_id: params[:template_id], signer_name: @cliente.nome, signer_email: @cliente.email,
      send_automatic_email: false, send_automatic_whatsapp: false,
      data: variaveis.map { |de, para| { de: de, para: para.presence || '________' } }
    }
  end

  # Convite (1ª vez) ou senha nova: a senha só existe em claro nesta resposta.
  def entregar_senha(cliente)
    registrar(cliente.convidado_em ? 'nova_senha' : 'convidou', nil, cliente)
    portal_json.linha(cliente).merge(Ramon::PortalConvite.new(cliente).perform)
  end

  def salvar_recados
    @cliente.update!(recados: params[:recados].to_unsafe_h.transform_values(&:to_s).compact_blank)
    registrar('salvou_recado')
  end

  def salvar_email
    @cliente.update!(email: params[:email].presence)
    registrar('alterou_email', @cliente.email)
  end

  def permissoes
    politica = PortalClientePolicy.new(pundit_user, :portal_cliente)
    { gerir_acesso: politica.gerir_acesso?, excluir: politica.destroy? }
  end

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
