# Área "Reuniões": gravações presenciais com transcrição (whisper local) e ata (LLM).
class Api::V1::Accounts::RamonReunioesController < Api::V1::Accounts::BaseController
  # Teto decimal do endpoint de transcrição (igual ao Messages::AudioTranscriptionService).
  AUDIO_BYTE_LIMIT = 25_000_000
  LIMIT = 100

  before_action :current_account
  before_action :fetch_reuniao, only: [:show, :update, :destroy, :reprocessar]
  before_action :check_authorization

  # q: busca no servidor por título ou nome do lead (alcança além das 100
  # mais recentes que a lista mostra sem busca).
  def index
    reunioes = Current.account.reunioes.includes(:user, :lead).recentes
    reunioes = buscar(reunioes, params[:q]) if params[:q].present?
    render json: { payload: reunioes.limit(LIMIT).map { |reuniao| linha(reuniao) } }
  end

  def show
    render json: detalhe(@reuniao)
  end

  def create
    audio = params[:audio]
    erro = audio_invalido(audio)
    return render_error(erro) if erro

    reuniao = Current.account.reunioes.create!(
      user: Current.user,
      titulo: params[:titulo].presence,
      duracao_segundos: params[:duracao_segundos].to_i,
      lead: Current.account.leads.find_by(id: params[:lead_id])
    )
    reuniao.audio.attach(audio)
    pedir_ata(reuniao, 'gravada')
    render json: detalhe(reuniao)
  end

  # Vincular a um lead (gravada pela barra lateral nasce sem lead); lead_id
  # vazio desvincula.
  def update
    lead = params[:lead_id].present? ? Current.account.leads.find(params[:lead_id]) : nil
    @reuniao.update!(lead: lead)
    render json: detalhe(@reuniao)
  end

  def destroy
    @reuniao.destroy!
    head :no_content
  end

  def reprocessar
    return render_error('Reunião não está com erro') unless @reuniao.status == 'erro'

    @reuniao.update!(status: 'transcrevendo', erro: nil)
    pedir_ata(@reuniao, 'refazer')
    render json: detalhe(@reuniao)
  end

  private

  # Regra fixa (08/10): a ata de sempre; o gatilho "Reunião gravada" ({evento} = gravada | refazer) só avisa os fluxos comuns.
  def pedir_ata(reuniao, evento)
    Ramon::ReuniaoAtaJob.perform_later(reuniao.id)
    Ramon::Fluxos::Disparo.externo('reuniao_gravada', reuniao, 'evento' => evento)
  end

  def buscar(reunioes, termo)
    padrao = "%#{ActiveRecord::Base.sanitize_sql_like(termo.to_s.strip)}%"
    reunioes.left_joins(:lead).where('ramon_reunioes.titulo ILIKE :q OR leads.name ILIKE :q', q: padrao)
  end

  def fetch_reuniao
    @reuniao = Current.account.reunioes.find(params[:id])
  end

  def check_authorization
    authorize(:reuniao, :"#{action_name}?")
  end

  def render_error(mensagem)
    render json: { error: mensagem }, status: :unprocessable_entity
  end

  # respond_to?(:content_type) cobre o caso de audio vir string (params malformado).
  def audio_invalido(audio)
    return 'Áudio ausente' if audio.blank?
    return 'Áudio acima do limite de 25 MB' if audio.size > AUDIO_BYTE_LIMIT
    return 'Arquivo não é áudio' unless audio.respond_to?(:content_type) && audio.content_type.to_s.start_with?('audio/')

    nil
  end

  def linha(reuniao)
    {
      id: reuniao.id,
      titulo: reuniao.titulo_exibicao,
      status: reuniao.status,
      duracao_segundos: reuniao.duracao_segundos,
      created_at: reuniao.created_at.iso8601,
      user_name: reuniao.user&.name,
      lead_id: reuniao.lead_id,
      lead_name: reuniao.lead&.name
    }
  end

  def detalhe(reuniao)
    linha(reuniao).merge(
      transcricao: reuniao.transcricao,
      ata: reuniao.ata,
      erro: reuniao.erro,
      audio_url: reuniao.audio.attached? ? url_for(reuniao.audio) : nil
    )
  end
end
