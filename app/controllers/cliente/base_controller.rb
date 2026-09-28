# Painel do Cliente: páginas ERB server-rendered com sessão em cookie
# criptografado (30 dias, host-only — não vaza pro chat.). Herda de
# ActionController::Base direto (CSRF padrão do Rails nos forms), como o
# Public::PortalController do link mágico.
class Cliente::BaseController < ActionController::Base
  COOKIE = :ramon_cliente
  SESSAO = 30.days
  # Entrou pelo código do e-mail: pode trocar a senha sem digitar a atual por 15 min.
  TROCA = :ramon_cliente_troca

  layout 'ramon_portal'

  helper_method :current_cliente

  private

  # O cookie guarda o id + um pedaço do digest da senha: trocar a senha ou gerar
  # senha provisória nova derruba toda sessão aberta com a senha antiga.
  def current_cliente
    return @current_cliente if defined?(@current_cliente)

    dados = cookies.encrypted[COOKIE]
    cliente = PortalCliente.find_by(id: dados['id']) if dados.is_a?(Hash)
    @current_cliente = cliente if cliente && ActiveSupport::SecurityUtils.secure_compare(dados['v'].to_s, versao(cliente))
  end

  def require_cliente
    redirect_to cliente_root_path if current_cliente.nil?
  end

  def entrar!(cliente)
    cliente.acessos.create!(ip: request.remote_ip) # Marco Civil art. 15
    cookies.encrypted[COOKIE] = { value: { 'id' => cliente.id, 'v' => versao(cliente) }, expires: SESSAO.from_now,
                                  httponly: true, same_site: :lax, secure: Rails.env.production? }
    @current_cliente = cliente
  end

  def sair!
    cookies.delete(COOKIE)
    cookies.delete(TROCA)
  end

  def versao(cliente) = cliente.senha_digest.to_s.last(8)
end
