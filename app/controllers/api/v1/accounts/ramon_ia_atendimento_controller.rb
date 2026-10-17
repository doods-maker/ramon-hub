# Tela "Como a IA atende": Marcador, Permissões e Gatilhos do padrão, de cada tese e de cada caixa. Só administrador.
# A validação é do Ramon::PerfilIa.gravar! (a fronteira de confiança); aqui só se recorta o que entra.
class Api::V1::Accounts::RamonIaAtendimentoController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    render json: Ramon::PerfilIa::Tela.new(Current.account).corpo
  end

  def update
    Ramon::PerfilIa.gravar!(Current.account, params.to_unsafe_h.slice('padrao', 'teses', 'caixas'))
    render json: Ramon::PerfilIa::Tela.new(Current.account).corpo
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def check_authorization
    authorize(:ramon_ia, :gerenciar?)
  end
end
