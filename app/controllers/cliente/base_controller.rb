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

  DIAS = %w[Domingo Segunda-feira Terça-feira Quarta-feira Quinta-feira Sexta-feira Sábado].freeze
  MESES = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro].freeze

  helper_method :current_cliente, :data_br, :hoje_extenso, :saudacao, :mes_curto

  private

  # 'YYYY-MM-DD' do espelho ou Date/Time → '03/10/2026' (o locale padrão do hub é en).
  def data_br(valor) = (valor.respond_to?(:strftime) ? valor : valor.to_s.to_date)&.strftime('%d/%m/%Y')

  def agora = Time.current.in_time_zone('America/Sao_Paulo')

  # "Sábado, 3 de outubro"
  def hoje_extenso = "#{DIAS[agora.wday]}, #{agora.day} de #{MESES[agora.month - 1]}"

  def saudacao
    return 'Bom dia' if agora.hour.between?(5, 11)

    agora.hour.between?(12, 17) ? 'Boa tarde' : 'Boa noite'
  end

  # Date → "set" (bloquinho de calendário do histórico)
  def mes_curto(data) = MESES[data.month - 1][0, 3]

  # O cookie guarda o id + um pedaço do digest da senha (+ a chave de sessão): trocar
  # a senha, gerar senha provisória nova ou suspender derruba toda sessão aberta.
  # Cliente suspenso nunca passa, mesmo com cookie válido.
  def current_cliente
    return @current_cliente if defined?(@current_cliente)

    dados = cookies.encrypted[COOKIE]
    cliente = PortalCliente.find_by(id: dados['id']) if dados.is_a?(Hash)
    @current_cliente = cliente if sessao_valida?(cliente, dados)
  end

  def sessao_valida?(cliente, dados)
    cliente.present? && !cliente.suspenso? && ActiveSupport::SecurityUtils.secure_compare(dados['v'].to_s, versao(cliente))
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

  # sessao_chave nil (quem nunca foi suspenso) mantém a versão de antes: ninguém cai no deploy.
  def versao(cliente) = "#{cliente.senha_digest.to_s.last(8)}#{cliente.sessao_chave}"
end
