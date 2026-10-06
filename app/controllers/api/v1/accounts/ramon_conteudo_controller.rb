# Tela "Conteúdo": kanban das peças do Instagram e ações de aprovação/agenda.
# Spec: docs/superpowers/specs/2026-10-02-conteudo-instagram-design.md §4.3
class Api::V1::Accounts::RamonConteudoController < Api::V1::Accounts::BaseController
  LIMIT = 200

  before_action :current_account
  before_action :fetch_peca, except: [:index]
  before_action :check_authorization
  before_action :recusar_se_refazendo, only: %i[agendar publicar_agora]
  before_action :recusar_se_no_ar, :exigir_conferencia, only: %i[tentar_de_novo voltar_prontas]

  rescue_from Peca::TransicaoInvalida do |e|
    render json: { error: "A peça mudou de etapa (#{e.message}). Recarregue a tela." }, status: :conflict
  end

  def index
    pecas = Current.account.pecas.where.not(status: 'reprovado').order(created_at: :desc).limit(LIMIT)
    render json: { payload: pecas.map { |peca| linha(peca) }, token_ig: GlobalConfigService.load('RAMON_IG_PUBLISH_TOKEN', nil).present? }
  end

  def show
    render json: detalhe(@peca)
  end

  def aprovar
    @peca.transicionar!(de: 'rascunho', para: 'aprovado', erro: nil)
    render json: detalhe(@peca)
  end

  def reprovar
    @peca.transicionar!(de: 'rascunho', para: 'reprovado', nota_reprovacao: params[:nota].presence)
    render json: detalhe(@peca)
  end

  def atualizar_legenda
    @peca.transicionar!(de: %w[montado agendado], para: @peca.status, legenda: params.require(:legenda))
    render json: detalhe(@peca)
  end

  def refazer
    cards = Array(params[:cards]).map(&:to_i).select { |n| n.between?(1, 5) }.uniq
    return render json: { error: 'Escolha ao menos um card' }, status: :unprocessable_entity if cards.empty?

    @peca.transicionar!(de: 'montado', para: 'montado', refazer_cards: cards)
    render json: detalhe(@peca)
  end

  def agendar
    quando = Time.zone.parse(params.require(:agendado_para).to_s)
    return render json: { error: 'Escolha um horário no futuro' }, status: :unprocessable_entity if quando.nil? || quando <= Time.current

    @peca.transicionar!(de: 'montado', para: 'agendado', agendado_para: quando)
    render json: detalhe(@peca)
  end

  def publicar_agora
    @peca.transicionar!(de: %w[montado agendado], para: 'agendado', agendado_para: Time.current)
    Ramon::PublicarPecasJob.perform_later
    render json: detalhe(@peca)
  end

  def cancelar_agendamento
    @peca.transicionar!(de: 'agendado', para: 'montado', agendado_para: nil)
    render json: detalhe(@peca)
  end

  def tentar_de_novo
    @peca.transicionar!(de: 'falhou', para: 'agendado', agendado_para: Time.current, erro: nil)
    Ramon::PublicarPecasJob.perform_later
    render json: detalhe(@peca)
  end

  # Falhou: volta pra Prontas pra corrigir a legenda e reagendar.
  def voltar_prontas
    @peca.transicionar!(de: 'falhou', para: 'montado', agendado_para: nil, erro: nil)
    render json: detalhe(@peca)
  end

  private

  # última barreira contra post duplicado: se a Meta já devolveu id, nunca republicar
  def recusar_se_no_ar
    return if @peca.ig_media_id.blank?

    render json: { error: 'Esta peça já foi ao ar — confira no Instagram.' }, status: :conflict
  end

  # Falha ambígua (pode ter ido ao ar): só segue com o "conferi no Instagram" marcado.
  def exigir_conferencia
    return unless @peca.publicacao_ambigua? && !ActiveModel::Type::Boolean.new.cast(params[:conferido])

    render json: { error: 'Confira no Instagram se o post não está lá antes de seguir.' }, status: :unprocessable_entity
  end

  def recusar_se_refazendo
    return if @peca.refazer_cards.blank?

    render json: { error: 'Há imagem sendo refeita — espere a peça voltar pra Prontas.' }, status: :conflict
  end

  def fetch_peca
    @peca = Current.account.pecas.find(params[:id])
  end

  def check_authorization
    authorize(:peca, :"#{action_name}?")
  end

  def linha(peca)
    {
      id: peca.id, slug: peca.slug, rodada: peca.rodada, tipo: peca.tipo, estilo: peca.estilo, tese: peca.tese,
      gancho: peca.gancho, status: peca.status, capa: peca.imagens.first, agendado_para: peca.agendado_para&.iso8601,
      erro: peca.erro, travada: peca.travada?, permalink: peca.permalink, ambigua: peca.publicacao_ambigua?
    }
  end

  def detalhe(peca)
    linha(peca).merge(conteudo: peca.conteudo, legenda: peca.legenda, imagens: peca.imagens,
                      nota_reprovacao: peca.nota_reprovacao,
                      sugestao_horario: peca.status == 'montado' ? Ramon::GradeConteudo.proximo_horario(peca.account)&.iso8601 : nil)
  end
end
