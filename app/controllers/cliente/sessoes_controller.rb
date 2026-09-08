class Cliente::SessoesController < Cliente::BaseController
  MENSAGEM_NEUTRA = 'Se este e-mail estiver cadastrado, você recebe um código em instantes.'.freeze
  MSG_CODIGO_INVALIDO = 'Código inválido ou vencido. Peça um novo código.'.freeze

  def new
    redirect_to cliente_inicio_path if current_cliente
  end

  # Resposta igual para e-mail conhecido e desconhecido (não revela quem tem conta).
  def create
    @email = email_param
    cliente = PortalCliente.from_email(@email)
    if cliente&.convidado_em.present?
      codigo = cliente.gerar_codigo!
      Ramon::PortalMailer.with(account: cliente.account, cliente: cliente, codigo: codigo).codigo.deliver_later
    end
    flash.now[:portal_notice] = MENSAGEM_NEUTRA
    render :codigo
  end

  def verificar
    @email = email_param
    cliente = PortalCliente.from_email(@email)
    if cliente&.codigo_valido?(params[:codigo])
      cliente.consumir_codigo!
      entrar!(cliente)
      redirect_to cliente_inicio_path
    else
      flash.now[:portal_alert] = MSG_CODIGO_INVALIDO
      render :codigo, status: :unprocessable_entity
    end
  end

  def destroy
    sair!
    redirect_to cliente_root_path
  end

  private

  def email_param = params[:email].to_s.strip.downcase
end
