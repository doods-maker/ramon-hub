# Equipe · chat interno (Fatia 2): canais Geral, por setor e 1:1. Participante
# lê e escreve; administrador lê qualquer canal (a tela avisa isso à equipe).
class Api::V1::Accounts::RamonChatController < Api::V1::Accounts::BaseController
  POR_PAGINA = 50

  before_action :canal, only: [:show, :enviar, :ler]
  before_action :check_authorization

  def index
    canais = ChatCanal.visiveis(Current.account, Current.user, admin: admin?)
    render json: { payload: canais.map { |c| c.push_data(Current.user) }, admin: admin? }
  end

  # ?antes=<id> = página anterior; volta em ordem cronológica.
  def show
    mensagens = @canal.mensagens.includes(:autor).order(id: :desc).limit(POR_PAGINA)
    mensagens = mensagens.where('id < ?', params[:antes]) if params[:antes].present?
    render json: { payload: mensagens.reverse.map(&:push_event_data), mais: mensagens.size == POR_PAGINA }
  end

  def enviar
    mensagem = @canal.mensagens.create!(autor: Current.user, conteudo: params[:conteudo].to_s.strip)
    @canal.marcar_lido!(Current.user)
    render json: mensagem.push_event_data
  end

  def ler
    @canal.marcar_lido!(Current.user)
    head :ok
  end

  def direto
    outro = Current.account.users.where.not(id: Current.user.id).find(params.require(:user_id))
    render json: ChatCanal.direto!(Current.account, Current.user, outro).push_data(Current.user)
  end

  private

  def canal
    @canal = Current.account.chat_canais.find(params[:id])
  end

  def admin?
    Current.account_user.administrator?
  end

  def check_authorization
    authorize(@canal || :chat_canal, :"#{action_name}?")
  end
end
