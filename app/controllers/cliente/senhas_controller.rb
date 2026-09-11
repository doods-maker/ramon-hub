# Trocar a senha (opcional): o cliente logado escolhe uma nova, só números, mín. 6.
class Cliente::SenhasController < Cliente::BaseController
  MSG_CONFIRMACAO = 'Digite a senha nova duas vezes, igual.'.freeze
  MSG_REGRA = 'A senha precisa ter só números, pelo menos 6.'.freeze
  MSG_OK = 'Senha trocada. Use a nova senha na próxima vez que entrar.'.freeze

  before_action :require_cliente

  def edit; end

  def update
    erro = validar(params[:senha].to_s, params[:confirmacao].to_s)
    if erro
      flash.now[:portal_alert] = erro
      render :edit, status: :unprocessable_entity
    else
      current_cliente.update!(senha: params[:senha].to_s)
      redirect_to cliente_inicio_path, flash: { portal_notice: MSG_OK }
    end
  end

  private

  def validar(senha, confirmacao)
    return MSG_CONFIRMACAO if senha.blank? || senha != confirmacao

    MSG_REGRA unless senha.match?(PortalCliente::REGRA_SENHA)
  end
end
