class Ramon::FunnelSnapshotService
  def initialize(account:, date: Time.zone.today)
    @account = account
    @date = date
  end

  def perform
    rows = build_rows
    FunnelSnapshot.transaction do
      # rubocop:disable Rails/SkipsModelValidations
      FunnelSnapshot.where(account_id: @account.id, snapshot_date: @date).delete_all
      FunnelSnapshot.insert_all(rows) if rows.any?
      # rubocop:enable Rails/SkipsModelValidations
    end
    rows.size
  end

  private

  # reorder(nil) anula o default_scope de ordenação do Lead, que quebra o
  # GROUP BY no Postgres (mesmo motivo do funnel_section do dashboard).
  def build_rows
    counts = @account.leads.funil.reorder(nil).group(:lead_stage_id, :thesis_id).count
    values = @account.leads.funil.reorder(nil).group(:lead_stage_id, :thesis_id).sum(:value)
    now = Time.current
    counts.filter_map do |(stage_id, thesis_id), count|
      stage = stages[stage_id]
      next unless stage

      row(stage, thesis_id, count, values[[stage_id, thesis_id]] || 0, now)
    end
  end

  def row(stage, thesis_id, count, value_sum, now)
    {
      account_id: @account.id, snapshot_date: @date,
      lead_stage_id: stage.id, stage_name: stage.name, stage_position: stage.position,
      is_won: stage.is_won, is_lost: stage.is_lost,
      thesis_id: thesis_id, thesis_name: thesis_names[thesis_id],
      leads_count: count, value_sum: value_sum,
      created_at: now, updated_at: now
    }
  end

  def stages
    @stages ||= @account.lead_stages.index_by(&:id)
  end

  def thesis_names
    @thesis_names ||= Thesis.where(account_id: @account.id).pluck(:id, :name).to_h
  end
end
