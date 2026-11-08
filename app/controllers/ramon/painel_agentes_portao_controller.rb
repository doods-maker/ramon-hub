# Portão do painel dos agentes: o forward_auth do Caddy chama aqui antes de cada requisição (ADR 0013).
# No 204 diz quem é e se escreve; o Caddy repassa ao painel e apaga o que o navegador mandar com esses nomes (ADR 0016).
class Ramon::PainelAgentesPortaoController < ApplicationController
  def show
    user = Ramon::PainelAgentes.usuario_da_sessao(cookies[Ramon::PainelAgentes::COOKIE])
    return head(:unauthorized) unless user

    response.headers['X-Painel-Usuario'] = user.email
    response.headers['X-Painel-Escreve'] = Ramon::PainelAgentes.decide?(user) ? '1' : '0'
    head :no_content
  end
end
