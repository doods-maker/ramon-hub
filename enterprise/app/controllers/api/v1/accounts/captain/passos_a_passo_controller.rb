# ramon (Etapa Documentos): imagens do passo a passo do assistente, uma por tema (Ramon::Documentos::PassoAPasso), na tela
# do assistente em Inteligência. Só administrador. Trocar ou remover apaga o arquivo do tema; a mensagem já enviada ao
# cliente tem a sua cópia.
class Api::V1::Accounts::Captain::PassosAPassoController < Api::V1::Accounts::BaseController
  LIMITE = 5.megabytes # imagem do WhatsApp
  TEMAS = Ramon::Documentos::PassoAPasso::TEMAS

  before_action :check_admin_authorization?
  before_action :set_assistant

  def index = render(json: corpo)

  def create
    arquivo = params[:file]
    return recusar('tema desconhecido') unless TEMAS.include?(params[:tema])
    return recusar('envie uma imagem de até 5 MB') unless imagem?(arquivo)

    da_tema(params[:tema])&.destroy
    @assistant.passos_a_passo.attach(io: arquivo.tempfile, content_type: arquivo.content_type,
                                     filename: "#{params[:tema]}#{File.extname(arquivo.original_filename.to_s)}")
    render json: corpo
  end

  def destroy
    da_tema(params[:tema])&.destroy
    render json: corpo
  end

  private

  def set_assistant
    @assistant = Captain::Assistant.for_account(Current.account.id).find(params[:assistant_id])
  end

  def imagem?(arquivo) = arquivo.respond_to?(:content_type) && arquivo.content_type.to_s.start_with?('image/') && arquivo.size <= LIMITE

  def da_tema(tema) = @assistant.passos_a_passo.find { |anexo| File.basename(anexo.filename.to_s, '.*') == tema }

  def recusar(erro) = render(json: { error: erro }, status: :unprocessable_entity)

  # ligado: a chave RAMON_ETAPA_DOCUMENTOS (a tela só mostra a seção com ela ligada).
  def corpo
    { ligado: Ramon::EtapaDeGanho.documentos_ligado?,
      temas: TEMAS.map do |tema|
        anexo = da_tema(tema)
        { tema: tema, nome: anexo&.filename&.to_s, url: anexo && rails_blob_path(anexo.blob, only_path: true) }
      end }
  end
end
