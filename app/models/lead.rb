class Lead < ApplicationRecord
  include LeadCadence

  PRESCRIPTION_WINDOW_MONTHS = 60

  belongs_to :account
  belongs_to :lead_stage
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  belongs_to :benefit_type, optional: true
  belongs_to :lead_priority, optional: true
  belongs_to :thesis, optional: true
  belongs_to :sdr, class_name: 'User', optional: true
  belongs_to :closer, class_name: 'User', optional: true
  has_many :lead_activities, dependent: :destroy_async
  has_many :lead_notes, dependent: :destroy_async
  has_many :lead_tasks, dependent: :destroy_async, inverse_of: :lead
  has_many :lead_triages, dependent: :destroy_async
  has_many :copilot_suggestions, dependent: :destroy_async

  validates :lead_stage, presence: true
  default_scope { order(:lead_stage_id, :position, :id) }

  # Caso de cálculo (tela Cálculos ← AdvBox): vive fora do funil comercial.
  FONTE_CALCULO = 'calculo-advbox'.freeze

  # NULL-safe: where.not(source:) excluiria os leads com source NULL junto.
  scope :funil, -> { where('leads.source IS DISTINCT FROM ?', FONTE_CALCULO) }

  # Lead "vivo" no funil — nem ganho nem perdido, e nunca caso de cálculo
  # (senão lead real de entrada seria adotado por um caso invisível no Kanban).
  # É o critério de reengajamento (pessoa ≠ caso): aberto reengaja, fechado
  # não trava lead novo.
  scope :open, -> { funil.joins(:lead_stage).where(lead_stages: { is_won: false, is_lost: false }) }

  before_save :track_stage_cycle
  before_save :assign_channel

  after_create_commit :dispatch_create_event
  after_update_commit :dispatch_update_event
  after_create_commit :record_created_activity
  after_update_commit :record_change_activities
  after_update_commit :generate_handoff_note, if: :saved_change_to_won_at?
  after_update_commit :enqueue_advbox_closing, if: :saved_change_to_won_at?
  after_update_commit :enqueue_nps_draft, if: :saved_change_to_won_at?

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity
  def push_event_data
    {
      id: id,
      name: name,
      lead_stage_id: lead_stage_id,
      benefit_type_id: benefit_type_id,
      lead_priority_id: lead_priority_id,
      thesis_id: thesis_id,
      contact_id: contact_id,
      conversation_id: conversation_id,
      position: position,
      # BigDecimal não é JSON nativo — Sidekiq strict_args rejeita no broadcast
      value: value&.to_f,
      source: source,
      channel: channel,
      stage_name: lead_stage&.name,
      stage_color: lead_stage&.color,
      benefit_type_name: benefit_type&.name,
      lead_priority_name: lead_priority&.name,
      thesis_name: thesis&.name,
      sdr_name: sdr&.name,
      closer_name: closer&.name,
      contact_name: contact&.name,
      latest_triage: latest_triage&.slice(:id, :status, :viability, :kit_status)
    }.merge(cadence_event_data)
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity

  def stalled?
    return false if lead_stage&.stalled_after_days.blank? || stage_entered_at.blank?

    stage_entered_at < lead_stage.stalled_after_days.days.ago
  end

  def dispatch_task_update
    dispatch_update_event
  end

  def latest_triage
    # Pré-carregado (índice do Kanban via includes): resolve na coleção em
    # memória — o jbuilder chama isto 4x/lead sem novas queries (mata o N+1).
    # Solto: ORDER+LIMIT 1, fresco a cada chamada. SEM memoização por instância:
    # `reload` limpa a associação mas não limparia um ivar, servindo triagem velha.
    lead_triages.loaded? ? lead_triages.max_by(&:id) : lead_triages.order(:id).last
  end

  # Resumo do CNIS anexado ao caso (Onda 3b) — só JSON nativo (vai no broadcast).
  def cnis_resumo
    return nil if cnis.blank?

    {
      filename: cnis['filename'],
      uploaded_at: cnis['uploaded_at'],
      nascimento: cnis.dig('entrada', 'segurado', 'nascimento'),
      competencias: cnis.dig('entrada', 'competencias')&.size || 0,
      vinculos: cnis['vinculos']&.size || 0,
      avisos: cnis['avisos'] || []
    }
  end

  # Portal do cliente (link mágico): token nasce sob demanda, nunca por callback.
  def ensure_portal_token!
    return portal_token if portal_token.present?

    update!(portal_token: SecureRandom.urlsafe_base64(24))
    portal_token
  end

  def prescription
    return nil if dcb_em.blank?

    today = Time.zone.today
    months = ((today.year - dcb_em.year) * 12) + (today.month - dcb_em.month)
    months -= 1 if today.day < dcb_em.day
    months = 0 if months.negative?
    lost = [months - PRESCRIPTION_WINDOW_MONTHS, 0].max
    {
      months_since_dcb: months,
      lost_installments: lost,
      lost_value: benefit_monthly_value.present? ? benefit_monthly_value * lost : nil
    }
  end

  private

  def assign_channel
    return if channel.present?

    self.channel = Ramon::SourceCatalog.derive(source) || 'outro'
  end

  def track_stage_cycle
    return unless will_save_change_to_lead_stage_id? || new_record?

    self.stage_entered_at = Time.current
    apply_stage_timestamps(LeadStage.find_by(id: lead_stage_id))
  end

  def apply_stage_timestamps(stage)
    won = stage&.is_won
    lost = stage&.is_lost
    self.won_at = won ? existing_or_now(won_at) : nil
    self.lost_at = lost ? existing_or_now(lost_at) : nil
    self.lost_reason = nil unless lost
  end

  def existing_or_now(current)
    current || Time.current
  end

  def generate_handoff_note
    return if won_at.blank?

    Leads::HandoffNoteService.new(lead: self).perform
  end

  # Item 21: fechamento → cliente/caso/tarefa no AdvBox (só com token configurado).
  def enqueue_advbox_closing
    return if won_at.blank? || ENV.fetch('ADVBOX_API_TOKEN', nil).blank?

    Ramon::AdvboxClosingJob.perform_later(id)
  end

  # NPS pós-fechamento (mapa comercial): rascunho de pesquisa quando vira ganho.
  def enqueue_nps_draft
    return if won_at.blank?

    Ramon::NpsDraftJob.perform_later(id)
  end

  def dispatch_create_event
    return if Current.suppress_import_events

    Rails.configuration.dispatcher.dispatch(Events::Types::LEAD_CREATED, Time.zone.now, lead: self)
  end

  def dispatch_update_event
    return if Current.suppress_import_events

    Rails.configuration.dispatcher.dispatch(Events::Types::LEAD_UPDATED, Time.zone.now, lead: self)
  end

  def record_created_activity
    lead_activities.create!(account: account, user: Current.user, kind: 'created', to_value: source)
  end

  def record_change_activities
    record_change('lead_stage_id', 'stage_changed') { |id| LeadStage.find_by(id: id)&.name }
    record_change('sdr_id', 'sdr_changed') { |id| User.find_by(id: id)&.name }
    record_change('closer_id', 'closer_changed') { |id| User.find_by(id: id)&.name }
    record_change('lead_priority_id', 'priority_changed') { |id| LeadPriority.find_by(id: id)&.name }
    record_change('thesis_id', 'thesis_changed') { |id| Thesis.find_by(id: id)&.name }
    record_change('value', 'value_changed') { |v| v&.to_s }
  end

  def record_change(attribute, kind)
    return unless saved_changes.key?(attribute)

    old_raw, new_raw = saved_changes[attribute]
    lead_activities.create!(
      account: account, user: Current.user, kind: kind,
      from_value: yield(old_raw), to_value: yield(new_raw)
    )
  end
end
