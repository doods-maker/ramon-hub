# Conferência de fases (tela do hub): processos judiciais ativos do ADVBOX com a etapa de lá ao lado do que o
# Painel do Cliente mostra. ?grupo=atrasada|baixa|diferente|igual &responsavel= &q= (cliente ou nº) &page=
# A equipe marca (painel certo/errado, atualizar etapa, observação); o administrador aplica as marcadas no ADVBOX.
class Api::V1::Accounts::RamonConferenciaFasesController < Api::V1::Accounts::BaseController
  POR_PAGINA = 50

  before_action :fetch_linha, only: [:update]
  before_action :check_authorization

  def index
    linhas = filtradas.order(:cliente, :id).includes(:marcado_por, :aplicado_por)
    pagina = [params[:page].to_i, 1].max
    render json: { payload: linhas.offset((pagina - 1) * POR_PAGINA).limit(POR_PAGINA).map { |l| linha_json(l) },
                   total: linhas.count, pagina: pagina, por_pagina: POR_PAGINA, resumo: resumo,
                   atualizado_em: base.maximum(:updated_at), permissoes: { aplicar: policy(:ramon_conferencia_fase).aplicar? },
                   etapas: etapas }
  end

  # Marcação da equipe: painel_marca (certo|errado|nil), etapa_id (etapa do ADVBOX ou nil para não alterar), obs.
  def update
    @linha.assign_attributes(params.permit(:painel_marca, :obs))
    @linha.escolher_etapa(etapa_pedida) if params.key?(:etapa_id)
    @linha.update!(marcado_por: Current.user, marcado_em: Time.current)
    render json: linha_json(@linha)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  def aplicar
    n = base.para_aplicar.count
    Ramon::ConferenciaAplicarJob.perform_later(Current.account.id, Current.user.id) if n.positive?
    render json: { enfileirados: [n, Ramon::ConferenciaFases::LIMITE_APLICAR].min }
  end

  private

  def base = Current.account.ramon_conferencias_fase

  # ADVBOX fora do ar não derruba a lista: a tela só desliga o seletor.
  def etapas
    Ramon::ConferenciaFases.etapas
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError
    []
  end

  # O nome e o grupo vêm do ADVBOX, nunca do navegador; etapa que não existe lá é 404.
  def etapa_pedida
    return if params[:etapa_id].blank?

    Ramon::ConferenciaFases.etapas.find { |e| e['etapa_id'] == params[:etapa_id].to_i } || raise(ActiveRecord::RecordNotFound)
  end

  def filtradas
    linhas = base
    linhas = linhas.where(grupo: params[:grupo]) if RamonConferenciaFase::GRUPOS.include?(params[:grupo])
    linhas = linhas.where(responsavel: params[:responsavel]) if params[:responsavel].present?
    if params[:q].present?
      termo = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].strip)}%"
      linhas = linhas.where('cliente ILIKE :t OR numero ILIKE :t', t: termo)
    end
    linhas
  end

  def resumo
    { grupos: base.group(:grupo).count, conferidos: base.where.not(painel_marca: nil).count,
      errados: base.where(painel_marca: 'errado').count, para_aplicar: base.para_aplicar.count,
      responsaveis: base.where.not(responsavel: nil).distinct.order(:responsavel).pluck(:responsavel) }
  end

  def linha_json(linha)
    linha.as_json(only: %i[id lawsuit_id numero cliente responsavel etapa_advbox etapa_advbox_id fase_advbox painel_titulo fase_painel grupo
                           tribunal agenda ultimo_andamento sugestao painel_marca obs marcado_em aplicado_em erro_aplicacao])
         .merge('marcado_por' => linha.marcado_por&.name, 'aplicado_por' => linha.aplicado_por&.name,
                'etapa_id' => (linha.alvo&.dig('etapa_id') if linha.atualizar))
  end

  def fetch_linha
    @linha = base.find(params[:id])
  end

  def check_authorization
    authorize(:ramon_conferencia_fase, :"#{action_name}?")
  end
end
