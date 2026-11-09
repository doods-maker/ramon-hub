# Extrato mensal da variável (playbook §13, item 6): o gestor vê todo mundo e
# lança a meta do mês; SDR/Closer veem só o próprio extrato (somente leitura).
# Mês fechado (regulamento §6) = o extrato guardado, com fechado_em; meta não muda mais.
# Duas grades (09/11/2026): papel sdr/closer = modelo A (meta + fator), hibrido = modelo B (Programa de Metas).
class Api::V1::Accounts::RamonExtratoController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  def show
    pessoas = Ramon::ExtratoFechamento.pessoas(Current.account, mes)
    pessoas = pessoas.select { |p| p[:user][:id] == Current.user.id } unless Current.account_user.administrator?
    render json: { mes: mes.strftime('%Y-%m'), grades: Ramon::ExtratoVariavel::GRADES, pessoas: pessoas }
  end

  def meta
    return render json: { error: 'mes_fechado' }, status: :unprocessable_entity if Ramon::ExtratoFechamento.fechado?(mes)

    user = Current.account.users.find(params[:user_id])
    registro = MetaComercial.find_or_initialize_by(account: Current.account, user: user, mes: mes)
    registro.update!(papel: params[:papel], meta: params[:meta].to_i, fator: params[:fator].presence || 1)
    render json: registro.slice(:user_id, :papel, :meta, :fator)
  end

  # Programas de Metas do híbrido (um por trimestre), mais recente primeiro.
  def programas
    render json: ProgramaMetas.where(account: Current.account).order(inicio: :desc).map { |p| programa_json(p) }
  end

  # Cria (sem id) ou edita o Programa. Programa que já pagou um mês fechado não muda.
  def programa
    do_escritorio = ProgramaMetas.where(account: Current.account)
    registro = params[:id].present? ? do_escritorio.find(params[:id]) : do_escritorio.new
    if registro.persisted? && Ramon::ExtratoFechamento.fechado?(registro.inicio)
      return render json: { error: 'mes_fechado' }, status: :unprocessable_entity
    end

    registro.update!(inicio: params[:inicio], fim: params[:fim], regras: regras_permitidas)
    render json: programa_json(registro)
  end

  private

  def programa_json(programa) = programa.slice(:id, :inicio, :fim, :regras)

  # Só o formato do Programa (ProgramaMetas): faixas, gás e constância.
  def regras_permitidas
    params.require(:regras).permit(faixas: [:min, :valor], gas: [:acima_de, :valor], constancia: [:min_mes, :max_problemas, :valor]).to_h
  end

  # ?mes=AAAA-MM; padrão = mês corrente no fuso do escritório.
  def mes
    @mes ||= if params[:mes].to_s.match?(/\A\d{4}-\d{2}\z/)
               Date.parse("#{params[:mes]}-01")
             else
               Time.current.in_time_zone(Ramon::ExtratoVariavel::TIME_ZONE).to_date.beginning_of_month
             end
  end

  def check_authorization
    authorize(:ramon_extrato, :"#{action_name}?")
  end
end
