# Painel do Cliente: páginas ERB server-rendered com sessão em cookie
# criptografado (30 dias, host-only — não vaza pro chat.). Herda de
# ActionController::Base direto (CSRF padrão do Rails nos forms), como o
# Public::PortalController do link mágico.
class Cliente::BaseController < ActionController::Base
  COOKIE = :ramon_cliente
  SESSAO = 30.days

  layout 'ramon_portal'

  helper_method :current_cliente

  private

  def current_cliente
    @current_cliente ||= PortalCliente.find_by(id: cookies.encrypted[COOKIE])
  end

  def require_cliente
    redirect_to cliente_root_path if current_cliente.nil?
  end

  def entrar!(cliente)
    cookies.encrypted[COOKIE] = { value: cliente.id, expires: SESSAO.from_now, httponly: true, same_site: :lax,
                                  secure: ActiveModel::Type::Boolean.new.cast(ENV.fetch('FORCE_SSL', false)) }
  end

  def sair!
    cookies.delete(COOKIE)
  end
end
