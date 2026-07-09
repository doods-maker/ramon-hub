class Api::V1::Accounts::RamonEsteiraController < Api::V1::Accounts::BaseController
  SNOOZE_TASK_TITLE = 'Retomar contato (adiado na Esteira)'.freeze

  before_action :current_account
  before_action :check_authorization
  before_action :set_lead, only: [:done, :snooze]

  def show
    render json: Ramon::EsteiraBuilder.new(account: Current.account).perform
  end

  # "Feito": registra a atividade e o builder tira o lead da fila do dia.
  def done
    @lead.lead_activities.create!(account: Current.account, user: Current.user, kind: Ramon::EsteiraBuilder::DONE_KIND)
    head :ok
  end

  # "Adiar": empurra a task do item pra frente; sem task, cria follow-up amanhã.
  def snooze
    task = @lead.lead_tasks.open_tasks.find_by(id: params[:task_id])
    if task
      # max com agora: task vencida há dias adia pra amanhã, não pra ontem.
      task.update!(due_at: [task.due_at, Time.current].max + 1.day)
    else
      @lead.lead_tasks.create!(account: Current.account, user: Current.user, kind: 'follow_up',
                               title: SNOOZE_TASK_TITLE, due_at: 1.day.from_now)
    end
    head :ok
  end

  private

  def set_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end

  def check_authorization
    authorize(:ramon_esteira, :"#{action_name}?")
  end
end
