# Portão do painel dos agentes: o forward_auth do Caddy chama aqui antes de cada requisição (ADR 0013).
class RamonPainelAgentesPortaoController < ApplicationController
  def show
    head(Ramon::PainelAgentes.sessao_liberada?(cookies[Ramon::PainelAgentes::COOKIE]) ? :no_content : :unauthorized)
  end
end
