# E-mails do Painel do Cliente: convite (com a senha provisória) e código de recuperação. Texto = gate do Eduardo.
class Ramon::PortalMailer < ApplicationMailer
  ASSUNTO_CONVITE = 'Acompanhe o seu caso pelo Painel do Cliente'.freeze
  ASSUNTO_CODIGO = 'Seu código de acesso ao Painel do Cliente'.freeze
  ASSUNTO_NOVIDADE = '%<nome>s, há uma novidade no seu caso'.freeze
  ASSUNTO_RESUMO = 'Painel do Cliente: %<n>d novidade(s) de clientes (%<data>s)'.freeze

  def codigo
    return unless smtp_config_set_or_development?

    @cliente = params[:cliente]
    @codigo = params[:codigo]
    mail(to: @cliente.email, subject: ASSUNTO_CODIGO) { |f| f.html { render layout: false } }
  end

  # itens: [{ 'tipo', 'titulo', 'o_que_esperar' }] — nunca número de processo.
  def novidade
    return unless smtp_config_set_or_development?

    @cliente = params[:cliente]
    @itens = params[:itens]
    @url = url_painel
    mail(to: @cliente.email, subject: format(ASSUNTO_NOVIDADE, nome: @cliente.primeiro_nome)) { |f| f.html { render layout: false } }
  end

  # Interno: 1 linha por novidade, com texto pronto de WhatsApp e link wa.me.
  def resumo_equipe
    return unless smtp_config_set_or_development?

    @linhas = params[:linhas]
    assunto = format(ASSUNTO_RESUMO, n: @linhas.size, data: I18n.l(Time.zone.today, format: '%d/%m'))
    mail(to: params[:para], subject: assunto) { |f| f.html { render layout: false } }
  end

  def convite
    return unless smtp_config_set_or_development?

    @cliente = params[:cliente]
    @senha = params[:senha]
    @url = url_painel
    mail(to: @cliente.email, subject: ASSUNTO_CONVITE) { |f| f.html { render layout: false } }
  end

  private

  def url_painel = ENV.fetch('PORTAL_URL', "#{ENV.fetch('FRONTEND_URL', nil)}/cliente")
end
