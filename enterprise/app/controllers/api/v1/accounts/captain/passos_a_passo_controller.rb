# ramon (Etapa Documentos): imagens do passo a passo do assistente, uma por tema (Ramon::Documentos::PassoAPasso), na tela
# do assistente em Inteligência. Só administrador e só no assistente ligado a uma etapa conduzida (o "Documentos"). Trocar
# ou remover apaga o arquivo do tema; a mensagem já enviada ao cliente tem a sua cópia.
class Api::V1::Accounts::Captain::PassosAPassoController < Api::V1::Accounts::BaseController
  LIMITE = 5.megabytes # imagem do WhatsApp
  TIPOS = { 'image/jpeg' => '.jpg', 'image/png' => '.png' }.freeze
  TEMAS = Ramon::Documentos::PassoAPasso::TEMAS

  before_action :check_admin_authorization?
  before_action :set_assistant
  before_action :so_da_etapa, only: [:create, :destroy]

  def index = render(json: corpo)

  def create
    arquivo = params[:file]
    return recusar('tema desconhecido') unless TEMAS.include?(params[:tema])

    tipo = tipo_real(arquivo)
    return recusar('envie uma imagem JPG ou PNG de até 5 MB') unless tipo && arquivo.size <= LIMITE

    da_tema(params[:tema])&.destroy
    @assistant.passos_a_passo.attach(io: arquivo.tempfile, content_type: tipo, filename: "#{params[:tema]}#{TIPOS[tipo]}")
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

  # Ligado a uma etapa conduzida (lead_stages.captain_assistant_id): só a rake ramon:documentos:assistente faz isso.
  def da_etapa? = Current.account.lead_stages.exists?(is_won: true, label: Ramon::EtapaDeGanho::CONDUZIDAS, captain_assistant_id: @assistant.id)

  def so_da_etapa = (recusar('este assistente não é o de uma etapa conduzida (Documentos)') unless da_etapa?)

  # Tipo pelos bytes do arquivo (o declarado pelo navegador mente fácil), só JPG ou PNG; senão nil.
  def tipo_real(arquivo)
    return unless arquivo.respond_to?(:tempfile)

    tipo = Marcel::MimeType.for(arquivo.tempfile)
    tipo if TIPOS.key?(tipo)
  end

  def da_tema(tema) = @assistant.passos_a_passo.find { |anexo| File.basename(anexo.filename.to_s, '.*') == tema }

  def recusar(erro) = render(json: { error: erro }, status: :unprocessable_entity)

  # ligado: a tela só mostra a seção no assistente da etapa conduzida.
  def corpo
    { ligado: da_etapa?,
      temas: TEMAS.map do |tema|
        anexo = da_tema(tema)
        { tema: tema, nome: anexo&.filename&.to_s, url: anexo && rails_blob_path(anexo.blob, only_path: true) }
      end }
  end
end
