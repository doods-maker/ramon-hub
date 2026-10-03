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
