# Cadastro dos passos do roteiro da tese (F2) — tela Playbooks: passos comuns (thesis_id nulo) e por tese.
# Salvar passa pela Ramon::Roteiro::Conferencia; editado na tela = edited (o seed da F4 não sobrescreve).
# A chave não muda depois de criada: respostas dos leads e "vai para" apontam por ela.
class Api::V1::Accounts::RoteiroPassosController < Api::V1::Accounts::BaseController
  CAMPOS = %w[id thesis_id position chave titulo orientacao tipo_resposta opcoes calculadora calculadora_campos saidas sem_perguntar edited].freeze

  before_action :check_authorization
  before_action :fetch_passo, only: [:update, :destroy]

  def index
    render json: { payload: escopo.map { |passo| passo.slice(*CAMPOS) }, calculadoras: Ramon::Roteiro::Calculadoras::CATALOGO }
  end

  def create
    salvar(escopo.new(passo_params.merge(thesis: tese, position: proxima_posicao, edited: true)))
  end

  def update
    @passo.assign_attributes(passo_params.except('chave').merge(edited: true))
    salvar(@passo)
  end

  def destroy
    usam = Ramon::Roteiro::Conferencia.referencias(@passo)
    return render_erro("Não dá para remover: #{usam.join(', ')} aponta para este passo.") if usam.any?

    @passo.destroy!
    head :ok
  end

  # Ordem feita na tela vale mais que o seed: quem mudou de lugar fica edited.
  def reorder
    ActiveRecord::Base.transaction do
      Array(params[:ids]).each_with_index do |id, i|
        passo = escopo.find(id)
        passo.update!(position: i, edited: true) if passo.position != i
      end
    end
    head :ok
  end

  private

  def escopo
    Current.account.roteiro_passos
  end

  def fetch_passo
    @passo = escopo.find(params[:id])
  end

  def tese
    Current.account.theses.find(params[:thesis_id]) if params[:thesis_id].present?
  end

  def proxima_posicao
    (escopo.where(thesis_id: params[:thesis_id].presence).maximum(:position) || -1) + 1
  end

  def salvar(passo)
    erros = Ramon::Roteiro::Conferencia.erros(passo)
    return render_erro(erros.join('; ')) if erros.any?

    passo.save!
    render json: passo.slice(*CAMPOS)
  end

  def render_erro(texto)
    render json: { error: texto }, status: :unprocessable_entity
  end

  def passo_params
    params.permit(:titulo, :chave, :orientacao, :tipo_resposta, :calculadora, :sem_perguntar,
                  opcoes: [], calculadora_campos: {},
                  saidas: [:id, :quando, :acao, :alvo, :motivo, :motivo_perda, :mensagem, { efeitos: %i[etiqueta etapa] }]).to_h
  end
end
