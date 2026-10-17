class LeadTask < ApplicationRecord
  KINDS = %w[follow_up document meeting other].freeze
  FORMATOS = %w[video whatsapp].freeze
  DURACAO = 30.minutes

  # Mudança que veio do Google: o hub aplica sem empurrar de volta (senão o cliente recebe o aviso do Google de novo).
  attr_accessor :sem_push_google
  # Marcada pela IA (piloto): a confirmação ao cliente pode sair sozinha (Ramon::ReuniaoAgendamento.confirmar).
  attr_accessor :confirmacao_automatica

  belongs_to :account
  belongs_to :lead
  belongs_to :user, optional: true
  belongs_to :agenda_user, class_name: 'User', optional: true

  validates :title, presence: true, length: { maximum: 255 }
  validates :kind, inclusion: { in: KINDS }
  validates :due_at, presence: true
  validates :formato, inclusion: { in: FORMATOS }

  scope :open_tasks, -> { where(completed_at: nil) }
  scope :overdue, -> { open_tasks.where(due_at: ...Time.current) }
  # "Hoje" no fuso do escritório (o servidor roda em UTC).
  scope :due_today, -> { open_tasks.where(due_at: Time.current.in_time_zone('America/Sao_Paulo').all_day) }

  before_create :atribuir_agenda_user, if: -> { kind == 'meeting' }
  after_create_commit :record_created_activity, :touch_lead
  after_update_commit :touch_lead
  after_create_commit :empurrar_para_google_criar, if: :reuniao_do_hub?
  after_update_commit :empurrar_para_google_atualizar, if: -> { reuniao_do_hub? && saved_changes.keys.intersect?(%w[due_at formato]) }
  after_destroy_commit :empurrar_para_google_cancelar, if: :reuniao_do_hub?

  # O rascunho de confirmação espera o Meet: a reunião vai pro Google de um dono com conta conectada (o job cria o rascunho).
  # ponytail: a conta é lida na marcação e de novo ao enfileirar; desconectar entre os dois é raro e o job cobre (cria sem Meet).
  def rascunho_no_job?
    reuniao_do_hub? && !sem_push_google && agenda_user.present? && GoogleAgendaConta.de(agenda_user).present?
  end

  # no_show: reunião em que o cliente não veio — conclui sem resultado de
  # reunião (o prêmio do SDR só conta a qualificada) e registra o no-show.
  def complete!(completing_user, no_show: false)
    update!(completed_at: Time.current)
    lead.lead_activities.create!(account: account, user: completing_user, kind: 'task_completed', to_value: title)
    return unless no_show && kind == 'meeting'

    lead.lead_activities.create!(account: account, user: completing_user, kind: 'meeting_no_show', to_value: title)
  end

  private

  # Dono da agenda da reunião: o Closer do lead ou o próximo da fila.
  def atribuir_agenda_user
    self.agenda_user_id ||= lead.closer_id || Ramon::Papeis.proximo(account, 'closer')&.id
  end

  # ponytail: legado do Cal.com, apagar quando não houver mais tarefas com o prefixo
  def reuniao_do_hub?
    kind == 'meeting' && !title.to_s.start_with?(Ramon::ReuniaoAgendamento::CALCOM_PREFIX)
  end

  # Reunião do hub vive no Google do dono (job: sem conta Google, sai calado). A linha some no destroy → dados vão no job.
  def empurrar_para_google_criar
    Ramon::GoogleAgendaPushJob.perform_later('criar', dados_do_push_criar) unless sem_push_google
  end

  def dados_do_push_criar
    { 'task_id' => id, 'rascunho' => (true if rascunho_no_job?), 'automatico' => (true if confirmacao_automatica) }.compact
  end

  def empurrar_para_google_atualizar
    Ramon::GoogleAgendaPushJob.perform_later('atualizar', { 'task_id' => id }) unless sem_push_google
  end

  def empurrar_para_google_cancelar
    return if sem_push_google

    # sem google_event_id gravado, o id fixo da criação ("hubtask<id>") acha o evento órfão; 404/410 são ignorados
    Ramon::GoogleAgendaPushJob.perform_later(
      'cancelar', { 'task_id' => id, 'google_event_id' => google_event_id.presence || "hubtask#{id}", 'agenda_user_id' => agenda_user_id }
    )
  end

  def record_created_activity
    lead.lead_activities.create!(account: account, user: Current.user, kind: 'task_created', to_value: title)
  end

  def touch_lead
    lead.dispatch_task_update
  end
end
