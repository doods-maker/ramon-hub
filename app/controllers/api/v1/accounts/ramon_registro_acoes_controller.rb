# Registro de ações: quem fez o quê, quando, e o que era antes — a trilha
# somente-inclusão (audits) da conta, filtrada e paginada. Só administrador.
# ?desde=&ate= (AAAA-MM-DD, fuso SP) &user_id= &tipo=lead|contato|conversa|dinheiro|acesso
# &q= (nome do lead/contato) &page= &todos=1 (CSV, até Ramon::RegistroAcoes::LIMITE_CSV)
class Api::V1::Accounts::RamonRegistroAcoesController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def index
    render json: Ramon::RegistroAcoes.new(Current.account, params.permit(:desde, :ate, :user_id, :tipo, :q, :page, :todos)).resultado
  end

  private

  def check_authorization
    authorize(:ramon_registro_acoes, :index?)
  end
end
