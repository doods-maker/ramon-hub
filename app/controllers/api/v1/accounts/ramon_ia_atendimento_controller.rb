# Tela "Como a IA atende": Marcador, Permissões e Gatilhos do padrão, de cada tese e de cada caixa, mais os limites gerais
# do escritório (Ramon::IaLimites). Só administrador. desfazer: { audit_id, alvo } regrava o valor de antes de uma linha
# do Registro de ações (tipo ia) só naquele alvo ('padrao' | 'tese:<id>' | 'caixa:<id>' | 'limites').
# A validação é do Ramon::PerfilIa.gravar! (a fronteira de confiança); aqui só se recorta o que entra.
class Api::V1::Accounts::RamonIaAtendimentoController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    render json: Ramon::PerfilIa::Tela.new(Current.account).corpo
  end

  def update
    corpo = params.to_unsafe_h
    # limites validados antes; perfis e limites vão no mesmo account.update!
    extra = corpo.key?('limites') ? Ramon::IaLimites.fragmento!(Current.account, corpo['limites']) : {}
    Ramon::PerfilIa.gravar!(Current.account, corpo.slice('padrao', 'teses', 'caixas'), extra)
    render json: Ramon::PerfilIa::Tela.new(Current.account).corpo
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def desfazer
    Ramon::PerfilIa::Historico.new(Current.account).desfazer!(params.require(:audit_id), params.require(:alvo).to_s)
    head :no_content
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def check_authorization
    authorize(:ramon_ia, :gerenciar?)
  end
end
