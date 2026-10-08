# ramon: rodadas dos Casos de teste da IA. "Rodar todos" enfileira uma rodada
# (uma por assistente por vez); a tela faz polling do show até concluir.
class Api::V1::Accounts::Captain::IaRodadasController < Api::V1::Accounts::BaseController
  LIMITE = 30

  before_action :current_account
  before_action -> { authorize(Captain::IaCaso, :gerenciar?) }
  before_action :set_assistant

  def index
    render json: { payload: escopo.recentes.limit(LIMITE).map(&:resumo), noturno: Captain::CadernoNoturno.ligado?(Current.account) }
  end

  def show
    rodada = escopo.find(params[:id])
    render json: rodada.as_json.merge(comparacao: rodada.comparacao)
  end

  def create
    Captain::IaRodada.destravar!(@assistant.id)
    return em_andamento if escopo.ativas.exists?

    total = Captain::IaCaso.ativos.where(assistant_id: @assistant.id).count
    return render(json: { error: 'Nenhum caso ativo para rodar.' }, status: :unprocessable_entity) if total.zero?

    rodada = escopo.create!(disparado_por: Current.user, total: total)
    Captain::IaRodadaJob.perform_later(rodada.id)
    render json: rodada.resumo
  rescue ActiveRecord::RecordNotUnique
    em_andamento
  end

  # I-X6: liga/desliga a rodada da madrugada da conta (vale para todos os assistentes).
  def noturno
    ligado = ActiveModel::Type::Boolean.new.cast(params[:ligado]) == true
    Current.account.update!(settings: (Current.account.settings || {}).merge(Ramon::CadernoNoturnoJob::CHAVE => ligado))
    render json: { noturno: ligado }
  end

  private

  def set_assistant
    @assistant = Captain::Assistant.for_account(Current.account.id).find(params[:assistant_id])
  end

  def escopo
    Captain::IaRodada.where(account_id: Current.account.id, assistant_id: @assistant.id)
  end

  def em_andamento
    render json: { error: 'Já tem uma rodada deste assistente em andamento.' }, status: :conflict
  end
end
