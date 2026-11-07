# Aba "Custos e metas" da área Marketing (spec 2026-11-07-marketing-trafego-design): só escreve e mostra o
# estado; os números moram no Metabase (aba Tráfego). Arquivos chegam como texto (o navegador lê o arquivo).
class Api::V1::Accounts::RamonMarketingController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  LIMITE_CUSTOS = 200

  def show
    render json: { status: status_meta, metas: resumo_metas, custos: custos.map { |c| custo_json(c) },
                   categorias: MarketingCusto::CATEGORIAS, teses: Current.account.theses.order(:name).map { |t| { id: t.id, name: t.name } } }
  end

  def criar_custo
    custo = MarketingCusto.create!(params.permit(:data, :valor, :categoria, :observacao)
                                         .merge(account: Current.account, user: current_user, thesis: tese))
    render json: custo_json(custo), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def remover_custo
    MarketingCusto.where(account: Current.account).find(params[:custo_id]).destroy!
    head :no_content
  end

  def importar_gasto
    render json: { linhas: Ramon::MetaGastoCsv.importar(Current.account, params.require(:texto)) }
  rescue Ramon::MetaGastoCsv::Erro => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Com meta editada à mão: 409 até a tela confirmar (confirmar: true).
  def importar_metas
    meses = Ramon::MetasDoModelo.importar(Current.account, params.require(:texto), confirmar: params[:confirmar].present?)
    render json: { meses: meses }
  rescue Ramon::MetasDoModelo::PrecisaConfirmar => e
    render json: { precisa_confirmar: true, editadas: e.editadas }, status: :conflict
  rescue Ramon::MetasDoModelo::Erro => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def metas_ativas
    metas.update_all(ativa: ActiveModel::Type::Boolean.new.cast(params[:ativas]) == true) # rubocop:disable Rails/SkipsModelValidations
    head :no_content
  end

  def editar_meta
    valor = BigDecimal(params.require(:valor).to_s, exception: false)
    return render json: { error: 'valor inválido' }, status: :unprocessable_entity if valor.nil? || valor.negative?

    meta = metas.find(params[:meta_id])
    meta.update!(valor: valor, editada_em: Time.current)
    render json: meta_json(meta)
  end

  def apagar_metas
    metas.delete_all
    head :no_content
  end

  private

  # Mesma regra dos Relatórios: só administrador.
  def check_authorization
    authorize(:ramon_relatorio, :show?)
  end

  # Só tese da própria conta (404 se vier id de outra).
  def tese
    Current.account.theses.find(params[:thesis_id]) if params[:thesis_id].present?
  end

  def custos
    MarketingCusto.where(account: Current.account).includes(:thesis).order(data: :desc, id: :desc).limit(LIMITE_CUSTOS)
  end

  def custo_json(custo)
    custo.slice(:id, :data, :valor, :categoria, :thesis_id, :observacao).merge(thesis_name: custo.thesis&.name)
  end

  def status_meta
    ultimo = MetaGasto.where(account: Current.account).order(:data, :updated_at).last
    { gasto: ligado?('RAMON_META_GASTO'), capi: ligado?('RAMON_META_CAPI'), insights_ig: ligado?('RAMON_IG_INSIGHTS'),
      conta_anuncios: ENV['RAMON_META_AD_ACCOUNT_ID'].present?, painel_trafego: ENV['RAMON_METABASE_MARKETING_ID'].to_i.positive?,
      ultimo_gasto: ultimo && { data: ultimo.data, origem: ultimo.origem, gravado_em: ultimo.updated_at },
      ultima_metrica_peca: Peca.where(account: Current.account).maximum(:metricas_em) }
  end

  def ligado?(chave) = ENV.fetch(chave, 'off') == 'on'

  def metas = MarketingMeta.where(account: Current.account)

  def resumo_metas
    { de: metas.minimum(:mes), ate: metas.maximum(:mes), atualizado_em: metas.maximum(:updated_at),
      ativas: metas.exists?(ativa: true), linhas: metas.order(:mes, :metrica).map { |m| meta_json(m) } }
  end

  def meta_json(meta)
    { id: meta.id, mes: meta.mes, metrica: meta.metrica, valor: meta.valor, editada: meta.editada_em.present? }
  end
end
