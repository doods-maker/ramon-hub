# API de conteúdo do Instagram pra rotina cloud (cria pauta) e pro worker de
# montagem na VPS. Token no header X-Conteudo-Token; conta fixa por env.
# Spec: docs/superpowers/specs/2026-10-02-conteudo-instagram-design.md §4.2
class Public::Api::V1::ConteudoController < PublicController
  before_action :verify_token

  def criar
    peca = conta.pecas.find_by(slug: params.require(:slug))
    return render json: { id: peca.id, status: peca.status }, status: :ok if peca

    peca = conta.pecas.create(peca_params)
    return render json: { error: peca.errors.full_messages.to_sentence }, status: :unprocessable_entity unless peca.persisted?

    render json: { id: peca.id, status: peca.status }, status: :created
  end

  def proxima
    peca = Peca.transaction do
      fila = conta.pecas.where(status: 'aprovado')
                  .or(conta.pecas.where(status: 'montado').where('cardinality(refazer_cards) > 0'))
      fila.order(:id).lock('FOR UPDATE SKIP LOCKED').first&.tap do |p|
        p.update!(status: 'montando', montagem_iniciada_em: Time.current)
      end
    end
    return head :no_content unless peca

    render json: peca.slice(:id, :slug, :rodada, :tipo, :conteudo, :refazer_cards)
  end

  def montada
    peca = conta.pecas.find(params[:id])
    peca.transicionar!(de: 'montando', para: 'montado', imagens: Array(params.require(:imagens)), refazer_cards: [],
                       erro: nil, montagem_iniciada_em: nil)
    head :no_content
  end

  # Refação que falha volta pra `montado` (as imagens antigas seguem válidas) e
  # zera refazer_cards — senão o worker pegaria a mesma peça a cada 30 s.
  def falha
    peca = conta.pecas.find(params[:id])
    destino = peca.refazer_cards.any? ? 'montado' : 'rascunho'
    peca.transicionar!(de: 'montando', para: destino, erro: params[:erro].to_s.truncate(2000), refazer_cards: [],
                       montagem_iniciada_em: nil)
    head :no_content
  end

  private

  def conta
    @conta ||= Account.find(ENV.fetch('RAMON_CONTEUDO_ACCOUNT_ID'))
  end

  def peca_params
    { slug: params[:slug], rodada: params.require(:rodada), tipo: params.require(:tipo), gancho: params.require(:gancho),
      estilo: params[:estilo], tese: params[:tese], notion_page_id: params[:notion_page_id],
      conteudo: params.require(:conteudo).to_unsafe_h }
  end

  def verify_token
    secret = ENV.fetch('RAMON_CONTEUDO_TOKEN', nil)
    provided = request.headers['X-Conteudo-Token'].to_s
    return if secret.present? && provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, secret)

    head :unauthorized
  end
end
