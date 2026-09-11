# Trocar a senha (opcional): o cliente logado escolhe uma nova, só números, mín. 6.
class Cliente::SenhasController < Cliente::BaseController
  before_action :require_cliente

  def edit; end

  def update
    if params[:senha].blank? || params[:senha].to_s != params[:confirmacao].to_s
      flash.now[:portal_alert] = 'Digite a senha nova duas vezes, igual.'
      return render :edit, status: :unprocessable_entity
    end
    if current_cliente.update(senha: params[:senha].to_s)
      redirect_to cliente_inicio_path, flash: { portal_notice: 'Senha trocada. Use a nova senha na próxima vez que entrar.' }
    else
      flash.now[:portal_alert] = current_cliente.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end
end
