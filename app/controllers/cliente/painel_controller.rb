class Cliente::PainelController < Cliente::BaseController
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
      flash[:portal_notice] = 'Dados atualizados.'
    else
      flash[:portal_notice] = 'Já atualizamos há pouco. Tente de novo mais tarde.'
    end
    redirect_to cliente_inicio_path
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError
    flash[:portal_alert] = 'Não conseguimos atualizar agora. Mostrando os últimos dados que temos.'
    redirect_to cliente_inicio_path
  end

  def processo
    @etapa = Ramon::PortalTexto.etapa(@processo['etapa'])
    @marcos = Ramon::PortalTexto.marcos(@processo['andamentos'])
    @recado = current_cliente.recados[@processo['id'].to_s]
    @pendentes = pendentes_com_status
  end

  # PR 5
  def enviar = head(:not_found)

  # PR 6
  def assinatura = head(:not_found)

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
end
