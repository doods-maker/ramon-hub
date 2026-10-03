# Tela "Conteúdo": kanban das peças do Instagram e ações de aprovação/agenda.
# Spec: docs/superpowers/specs/2026-10-02-conteudo-instagram-design.md §4.3
class Api::V1::Accounts::RamonConteudoController < Api::V1::Accounts::BaseController
  LIMIT = 200

  before_action :current_account
  before_action :fetch_peca, except: [:index]
  before_action :check_authorization

  rescue_from Peca::TransicaoInvalida do |e|
    render json: { error: "A peça mudou de etapa (#{e.message}). Recarregue a tela." }, status: :conflict
  end

  def index
    pecas = Current.account.pecas.where.not(status: 'reprovado').order(created_at: :desc).limit(LIMIT)
    render json: { payload: pecas.map { |peca| linha(peca) } }
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

  private

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
      erro: peca.erro, travada: peca.travada?, permalink: peca.permalink
    }
  end

  def detalhe(peca)
    linha(peca).merge(conteudo: peca.conteudo, legenda: peca.legenda, imagens: peca.imagens,
                      nota_reprovacao: peca.nota_reprovacao)
  end
end
