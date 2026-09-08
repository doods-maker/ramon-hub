class Cliente::PainelController < Cliente::BaseController
  MSG_ATUALIZADO = 'Dados atualizados.'.freeze
  MSG_AGUARDE = 'Já atualizamos há pouco. Tente de novo mais tarde.'.freeze
  MSG_INDISPONIVEL = 'Não conseguimos atualizar agora. Mostrando os últimos dados que temos.'.freeze
  MSG_ARQUIVO_INVALIDO = 'Não foi possível receber o arquivo — envie um PDF ou foto (JPG/PNG/HEIC) de até 10 MB.'.freeze
  MSG_RECEBIDO = 'Recebemos seu documento. Obrigado!'.freeze

  MAX_UPLOAD_BYTES = 10.megabytes
  ALLOWED_CONTENT_TYPES = %w[application/pdf image/jpeg image/jpg image/png image/heic image/heif].freeze

  before_action :require_cliente
  before_action :require_termos, except: [:aceitar_termos]
  before_action :fetch_processo, only: [:processo, :enviar]

  def show
    @ativos, @encerrados = current_cliente.processos.partition { |p| !Ramon::PortalTexto.encerrado?(p['fase']) }
    @assinaturas = current_cliente.assinaturas.pendentes
  end

  def aceitar_termos
    current_cliente.update!(termos_aceitos_em: Time.current) if params[:aceite] == '1'
    redirect_to cliente_inicio_path
  end

  def atualizar
    if current_cliente.pode_atualizar?
      current_cliente.update!(atualizacao_pedida_em: Time.current)
      Ramon::PortalSyncService.new(current_cliente).perform
      flash[:portal_notice] = MSG_ATUALIZADO
    else
      flash[:portal_notice] = MSG_AGUARDE
    end
    redirect_to cliente_inicio_path
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError
    flash[:portal_alert] = MSG_INDISPONIVEL
    redirect_to cliente_inicio_path
  end

  def processo
    @etapa = Ramon::PortalTexto.etapa(@processo['etapa'])
    @marcos = Ramon::PortalTexto.marcos(@processo['andamentos'])
    @recado = current_cliente.recados[@processo['id'].to_s]
    @pendentes = pendentes_com_status
  end

  def enviar
    return redirect_arquivo_invalido unless upload_valido?

    envio = criar_envio!
    Ramon::PortalEnvioJob.perform_later(envio.id)
    flash[:portal_notice] = MSG_RECEBIDO
    redirect_to cliente_processo_path(@processo['id'])
  end

  def assinatura
    @assinatura = current_cliente.assinaturas.find_by(id: params[:id])
    head :not_found if @assinatura.nil?
  end

  private

  def require_termos
    render :termos unless current_cliente.termos_aceitos?
  end

  def fetch_processo
    @processo = current_cliente.processo(params[:lawsuit_id])
    head :not_found if @processo.nil?
  end

  # Item pedido vira "enviado" quando existe PortalEnvio do mesmo pedido (post_id) e item.
  def pendentes_com_status
    enviados = current_cliente.envios.where(lawsuit_id: @processo['id']).pluck(:solicitacao_post_id, :item).to_set
    @processo['docs_pendentes'].map { |d| d.merge('enviado' => enviados.include?([d['post_id'], d['item']])) }
  end

  # Tipo real por magic bytes (Marcel) — o content_type do browser mente fácil.
  def upload_valido?
    file = params[:file]
    return false unless file.respond_to?(:tempfile) && params[:item].present?

    ALLOWED_CONTENT_TYPES.include?(Marcel::MimeType.for(file.tempfile)) && file.size.to_i.positive? && file.size <= MAX_UPLOAD_BYTES
  end

  def criar_envio!
    envio = current_cliente.envios.create!(lawsuit_id: @processo['id'], solicitacao_post_id: params[:post_id].presence,
                                           item: params[:item].to_s.strip.first(120))
    envio.arquivo.attach(params[:file])
    envio
  end

  def redirect_arquivo_invalido
    flash[:portal_alert] = MSG_ARQUIVO_INVALIDO
    redirect_to cliente_processo_path(@processo['id'])
  end
end
