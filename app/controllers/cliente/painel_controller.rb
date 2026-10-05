class Cliente::PainelController < Cliente::BaseController
  MSG_ATUALIZADO = 'Dados atualizados.'.freeze
  MSG_AGUARDE = 'Já atualizamos há pouco. Tente de novo mais tarde.'.freeze
  MSG_INDISPONIVEL = 'Não conseguimos atualizar agora. Mostrando os últimos dados que temos.'.freeze
  MSG_ARQUIVO_INVALIDO = 'Não foi possível receber o arquivo — envie um PDF ou foto (JPG/PNG/HEIC) de até 10 MB.'.freeze
  MSG_RECEBIDO = 'Recebemos seu documento. Obrigado!'.freeze
  MSG_DOC_INDISPONIVEL = 'Não conseguimos buscar o documento agora. Tente de novo mais tarde.'.freeze

  MAX_UPLOAD_BYTES = 10.megabytes
  ALLOWED_CONTENT_TYPES = %w[application/pdf image/jpeg image/jpg image/png image/heic image/heif].freeze

  before_action :require_cliente
  before_action -> { current_cliente.registrar_acesso!(request.remote_ip) }, only: [:show, :processo]
  before_action :require_termos, except: [:aceitar_termos]
  before_action :fetch_processo, only: [:processo, :enviar]

  helper_method :pendencias, :a_enviar

  def show
    @ativos, @encerrados = current_cliente.processos.partition { |p| !Ramon::PortalTexto.encerrado?(p['fase']) }
    @assinaturas = current_cliente.assinaturas.pendentes
    tons = @ativos.map { |p| Ramon::PortalTexto.status(p).first }
    @resumo = { fazer: pendencias, andamento: tons.count { |t| %w[andamento analise].include?(t) }, aprovado: tons.count('aprovado') }
  end

  # Aba Documentos: o que falta enviar (de todos os processos), o que assinar e o que já está com o escritório.
  def documentos
    @assinaturas = current_cliente.assinaturas.pendentes
    @assinadas = current_cliente.assinaturas.where(status: 'signed').order(assinado_em: :desc)
    @envios = current_cliente.envios.with_attached_arquivo.order(created_at: :desc).limit(20)
  end

  def equipe
    @responsaveis = current_cliente.processos.filter_map { |p| p['responsavel'].to_s.titleize.presence }.uniq
  end

  def conta; end

  # Autorização da IA (LGPD art. 33, VIII): opcional, pergunta no início até responder.
  def consentir_ia
    current_cliente.update!(ia_consentimento: params[:ia] == 'sim')
    redirect_to cliente_inicio_path
  end

  def aceitar_termos
    current_cliente.update!(termos_aceitos_em: Time.current) if params[:aceite] == '1'
    redirect_to Ramon::PortalTexto.v2? ? cliente_boas_vindas_path : cliente_inicio_path
  end

  # Onboarding de 3 telas (?passo=1..3). Sem coluna própria: só aparece logo após o
  # aceite dos termos, que acontece 1x. Texto novo = só com PORTAL_TEXTOS_V2.
  def boas_vindas
    return redirect_to cliente_inicio_path unless Ramon::PortalTexto.v2?

    @passo = params[:passo].to_i.clamp(1, 3)
  end

  def atualizar
    if current_cliente.pode_atualizar?
      sincronizar_agora!
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
    @etapa = Ramon::PortalTexto.etapa(PortalCliente.etapa_cliente(@processo))
    @novidades = PortalCliente.novidades_nao_vistas(@processo)
    current_cliente.marcar_vistas!(@processo['id']) if @novidades.any?
    @marcos = Ramon::PortalTexto.marcos(@processo['andamentos'])
    @recado = current_cliente.recados[@processo['id'].to_s]
    @pendentes = current_cliente.pendentes_com_status(@processo)
    @linha = Ramon::PortalTexto.linha_do_tempo(@processo) if Ramon::PortalTexto.v2?
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

  # Download só do que o próprio cliente assinou (link temporário do ZapSign) ou
  # enviou. Documento do ADVBOX nunca (regra do Eduardo, 28/09/2026).
  def baixar_assinatura
    assinada = current_cliente.assinaturas.find_by(id: params[:id], status: 'signed')
    return head :not_found if assinada.nil?

    url = Ramon::ZapsignClient.doc(assinada.doc_token)&.dig('signed_file')
    url.present? ? redirect_to(url, allow_other_host: true) : doc_indisponivel
  rescue Ramon::ZapsignClient::UnavailableError, Ramon::ZapsignClient::RequestError
    doc_indisponivel
  end

  def baixar_envio
    envio = current_cliente.envios.find_by(id: params[:id])
    return head :not_found unless envio&.arquivo&.attached?

    send_data envio.arquivo.download, filename: envio.arquivo.filename.to_s, type: envio.arquivo.content_type, disposition: 'attachment'
  end

  private

  def doc_indisponivel = redirect_to(cliente_inicio_path, flash: { portal_alert: MSG_DOC_INDISPONIVEL })

  # Só carimba atualizacao_pedida_em (o gate das 6h) depois do sync dar certo —
  # se o ADVBOX cair, o rescue acima nunca chega aqui e o cliente não fica travado.
  def sincronizar_agora!
    Ramon::PortalSyncService.new(current_cliente).perform
    current_cliente.update!(atualizacao_pedida_em: Time.current)
  end

  def require_termos
    render :termos unless current_cliente.termos_aceitos?
  end

  def fetch_processo
    @processo = current_cliente.processo(params[:lawsuit_id])
    head :not_found if @processo.nil?
  end

  # [[processo, doc]] ainda não enviados, de todos os processos ativos (regra no model).
  def a_enviar = current_cliente.a_enviar

  # Contador do menu (aba Documentos) e do resumo do início.
  def pendencias = @pendencias ||= a_enviar.size + current_cliente.assinaturas.pendentes.count

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
