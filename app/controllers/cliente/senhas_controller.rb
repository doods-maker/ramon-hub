# Trocar a senha (opcional): o cliente logado escolhe uma nova, só números, mín. 6.
class Cliente::SenhasController < Cliente::BaseController
  MSG_CONFIRMACAO = 'Digite a senha nova duas vezes, igual.'.freeze
  MSG_REGRA = 'A senha precisa ter só números, pelo menos 6.'.freeze
  MSG_OK = 'Senha trocada. Use a nova senha na próxima vez que entrar.'.freeze
  MSG_ATUAL = 'A senha atual não confere.'.freeze

  before_action :require_cliente

  helper_method :pedir_senha_atual?

  def edit; end

  def update
    erro = validar(params[:senha].to_s, params[:confirmacao].to_s)
    if erro
      flash.now[:portal_alert] = erro
      render :edit, status: :unprocessable_entity
    else
      current_cliente.update!(senha: params[:senha].to_s)
      cookies.delete(TROCA)
      entrar!(current_cliente) # a senha mudou: renova o cookie desta sessão, as outras caem
      redirect_to cliente_inicio_path, flash: { portal_notice: MSG_OK }
    end
  end

  private

  def pedir_senha_atual?
    cookies.encrypted[TROCA] != current_cliente.id
  end

  def validar(senha, confirmacao)
    return MSG_ATUAL if pedir_senha_atual? && !current_cliente.authenticate_senha(params[:senha_atual].to_s)
    return MSG_CONFIRMACAO if senha.blank? || senha != confirmacao

    MSG_REGRA unless senha.match?(PortalCliente::REGRA_SENHA)
  end
end
