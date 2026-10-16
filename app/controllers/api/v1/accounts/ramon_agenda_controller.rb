# Compromissos do Google do comercial na tela Agenda. Admin ou membro de sdr/closer; ids fora do comercial são ignorados.
class Api::V1::Accounts::RamonAgendaController < Api::V1::Accounts::BaseController
  CACHE_TTL = 2.minutes
  MAX_DIAS = 70
  ERROS = [Ramon::GoogleAgenda::Cliente::SemConexao, Ramon::GoogleAgenda::Cliente::Erro, Ramon::GoogleAgenda::Cliente::Transitorio].freeze

  before_action :check_acesso
  before_action :parse_periodo

  def google
    pedidos = params[:user_ids].present? ? Array(params[:user_ids]).map(&:to_i) & membro_ids : membro_ids
    payload, erros = coletar(GoogleAgendaConta.conectadas.where(user_id: pedidos))
    render json: { payload: payload.sort_by { |e| e[:inicio] }, erros: erros, membros: membros }
  end

  private

  def coletar(contas)
    payload = []
    erros = []
    contas.find_each do |conta|
      payload.concat(eventos_de(conta))
    rescue *ERROS => e
      # LGPD: só a classe e os ids, nunca título nem mensagem.
      Rails.logger.warn "Ramon agenda: google falhou (#{e.class}) user=#{conta.user_id}"
      erros << conta.user_id
    end
    [payload, erros]
  end

  def eventos_de(conta)
    Rails.cache.fetch("ramon_agenda_google:#{conta.user_id}:#{@from.iso8601}:#{@to.iso8601}", expires_in: CACHE_TTL) do
      Ramon::GoogleAgenda::Cliente.new(conta).eventos(de: @from, ate: @to)
                                  .reject { |e| e[:cancelado] || e[:hub_task_id].present? }
                                  .map { |e| { user_id: conta.user_id, inicio: e[:inicio], fim: e[:fim], titulo: e[:titulo] } }
    end
  end

  def membro_ids
    @membro_ids ||= [Ramon::Papeis::SDR, Ramon::Papeis::CLOSER].flat_map { |p| Ramon::Papeis.membro_ids(Current.account, p) }.uniq
  end

  def membros
    User.where(id: membro_ids).order(:name).map { |u| { id: u.id, name: u.name } }
  end

  def check_acesso
    return if Current.account_user.administrator? || membro_ids.include?(Current.user.id)

    head :forbidden
  end

  def parse_periodo
    @from = Time.zone.parse(params[:from].to_s)
    @to = Time.zone.parse(params[:to].to_s)
    return if @from && @to && @to > @from && (@to - @from) <= MAX_DIAS.days

    head :unprocessable_entity
  rescue ArgumentError
    head :unprocessable_entity
  end
end
