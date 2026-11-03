# Diz à tela onde está o painel dos agentes. url nula = esta pessoa não tem acesso (ADR 0013).
class Api::V1::Accounts::RamonPainelAgentesController < Api::V1::Accounts::BaseController
  def show
    render json: { url: Ramon::PainelAgentes.url_para(Current.user) }
  end
end
