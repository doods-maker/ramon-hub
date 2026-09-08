# E-mails do Painel do Cliente: código de acesso e convite. Texto = gate do Eduardo.
class Ramon::PortalMailer < ApplicationMailer
  ASSUNTO_CONVITE = 'Acompanhe o seu caso pelo Painel do Cliente'.freeze
  ASSUNTO_CODIGO = 'Seu código de acesso ao Painel do Cliente'.freeze

  def codigo
    return unless smtp_config_set_or_development?

    @cliente = params[:cliente]
    @codigo = params[:codigo]
    mail(to: @cliente.email, subject: ASSUNTO_CODIGO) { |f| f.html { render layout: false } }
  end

  def convite
    return unless smtp_config_set_or_development?

    @cliente = params[:cliente]
    @url = ENV.fetch('PORTAL_URL', "#{ENV.fetch('FRONTEND_URL', nil)}/cliente")
    mail(to: @cliente.email, subject: ASSUNTO_CONVITE) { |f| f.html { render layout: false } }
  end
end
