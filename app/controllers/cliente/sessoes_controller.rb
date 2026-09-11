class Cliente::SessoesController < Cliente::BaseController
  MSG_LOGIN_INVALIDO = 'CPF ou senha não conferem.'.freeze
  MENSAGEM_NEUTRA = 'Se houver um e-mail cadastrado para este CPF, você recebe um código em instantes. ' \
                    'Sem e-mail? Fale com a equipe pelo WhatsApp para receber uma senha nova.'.freeze
  MSG_CODIGO_INVALIDO = 'Código inválido ou vencido. Peça um novo código.'.freeze

  def new
    redirect_to cliente_inicio_path if current_cliente
  end

  # CPF + senha. Mesma mensagem para CPF desconhecido e senha errada.
  def create
    cliente = PortalCliente.from_cpf(params[:cpf])
    if cliente&.convidado_em.present? && cliente.authenticate_senha(params[:senha].to_s)
      entrar!(cliente)
      redirect_to cliente_inicio_path
    else
      flash.now[:portal_alert] = MSG_LOGIN_INVALIDO
      render :new, status: :unprocessable_entity
    end
  end

  # "Esqueci a senha": pede o CPF.
  def esqueci; end

  # Manda o código de 6 dígitos pro e-mail, se houver. Resposta igual pra CPF
  # conhecido, desconhecido ou sem e-mail (não revela quem tem conta).
  def codigo
    @cpf = cpf_param
    cliente = PortalCliente.from_cpf(@cpf)
    if cliente&.convidado_em.present? && cliente.email.present?
      codigo = cliente.gerar_codigo!
      Ramon::PortalMailer.with(account: cliente.account, cliente: cliente, codigo: codigo).codigo.deliver_later
    end
    flash.now[:portal_notice] = MENSAGEM_NEUTRA
    render :codigo
  end

  # Entra pelo código e leva pra escolher uma senha nova.
  def verificar
    @cpf = cpf_param
    cliente = PortalCliente.from_cpf(@cpf)
    if cliente&.codigo_valido?(params[:codigo])
      cliente.consumir_codigo!
      entrar!(cliente)
      redirect_to edit_cliente_senha_path
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

  def cpf_param = params[:cpf].to_s.delete('^0-9')
end
