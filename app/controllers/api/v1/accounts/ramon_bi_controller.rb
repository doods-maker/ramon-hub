class Api::V1::Accounts::RamonBiController < Api::V1::Accounts::BaseController
  before_action :current_account

  MAX_BYTES = 5.megabytes

  def show
    authorize(:ramon_bi, :show?)
    render json: payload
  end

  def update
    authorize(:ramon_bi, :update?)
    arquivo = params[:arquivo]
    erro = validar(arquivo)
    return render json: { error: erro }, status: :unprocessable_entity if erro

    # attach troca o anexo anterior: o hub guarda só a versão mais nova.
    Current.account.ramon_bi.attach(
      io: arquivo.tempfile, filename: 'bi-escritorio.html', content_type: 'text/html',
      metadata: { enviado_por: Current.user.name }
    )
    render json: payload
  end

  private

  def validar(arquivo)
    return 'Envie o arquivo do BI.' unless arquivo.respond_to?(:tempfile)

    html = File.extname(arquivo.original_filename.to_s).casecmp?('.html') && arquivo.content_type == 'text/html'
    return 'O arquivo precisa ser um .html.' unless html

    'O arquivo passa de 5 MB.' if arquivo.size > MAX_BYTES
  end

  def payload
    anexo = Current.account.ramon_bi
    return { enviado: false } unless anexo.attached?

    blob = anexo.blob
    { enviado: true, html: anexo.download.force_encoding('UTF-8'), enviado_em: blob.created_at.iso8601,
      enviado_por: blob.metadata['enviado_por'] }
  end
end
