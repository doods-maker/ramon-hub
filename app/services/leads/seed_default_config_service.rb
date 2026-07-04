class Leads::SeedDefaultConfigService
  STAGES = [
    { name: 'Novo', label: 'fase-novo', color: '#6b7280', is_won: false, is_lost: false },
    { name: 'Qualificação', label: 'fase-qualificacao', color: '#3b82f6', is_won: false, is_lost: false },
    { name: 'Reunião agendada', label: 'fase-reuniao-agendada', color: '#8b5cf6', is_won: false, is_lost: false },
    { name: 'Reunião realizada', label: 'fase-reuniao-realizada', color: '#06b6d4', is_won: false, is_lost: false },
    { name: 'Negociação', label: 'fase-negociacao', color: '#f59e0b', is_won: false, is_lost: false },
    { name: 'Última chance', label: 'fase-ultima-chance', color: '#ef4444', is_won: false, is_lost: false },
    { name: 'Fechado', label: 'fase-fechado', color: '#22c55e', is_won: true, is_lost: false },
    { name: 'Perdido', label: 'fase-perdido', color: '#71717a', is_won: false, is_lost: true }
  ].freeze

  # [probability, stalled_after_days] por etapa — mesmos valores da migração AddCadenceToRamonCrm.
  STAGE_CADENCE = {
    'Novo' => [10, 2], 'Qualificação' => [20, 3], 'Reunião agendada' => [40, nil],
    'Reunião realizada' => [60, 5], 'Negociação' => [75, 5], 'Última chance' => [50, 7],
    'Fechado' => [100, nil], 'Perdido' => [0, nil]
  }.freeze

  BENEFITS = ['Aposentadoria', 'BPC/LOAS', 'Auxílio-doença', 'Auxílio-acidente',
              'Pensão por morte', 'Trabalhista', 'Outro'].freeze

  LOST_REASONS = ['Sem viabilidade', 'Sumiu / não respondeu', 'Honorário',
                  'Foi para concorrente', 'Fora da área', 'Outro'].freeze

  PRIORITIES = [
    { name: 'Alta', weight: 3 },
    { name: 'Média', weight: 2 },
    { name: 'Baixa', weight: 1 }
  ].freeze

  THESES_SEED_PATH = Rails.root.join('db/seeds/ramon/theses_seed.yml')
  TRIAGE_AGENTS_SEED_PATH = Rails.root.join('db/seeds/ramon/triage_agents_seed.yml')

  def initialize(account)
    @account = account
  end

  def perform
    seed_stages
    seed_benefits
    seed_priorities
    seed_lost_reasons
    seed_theses
    seed_triage_agents
  end

  # NÃO criamos as Labels fase-* aqui: criá-las em toda conta poluiria a
  # enumeração global de labels (vários specs nativos do Chatwoot assumem
  # contas sem labels). As Labels fase-* nascem SOB DEMANDA em
  # Ramon::StageLabelSync, quando uma etapa é de fato aplicada numa conversa.
  def self.color_for(label)
    STAGES.find { |s| s[:label] == label }&.dig(:color) || '#1f93ff'
  end

  private

  def seed_stages
    STAGES.each_with_index do |attrs, i|
      cadence = STAGE_CADENCE[attrs[:name]]
      stage = @account.lead_stages.find_or_create_by!(name: attrs[:name]) do |s|
        apply_stage_attributes(s, attrs, i, cadence)
      end
      reconcile_stage(stage, attrs, cadence)
    end
  end

  def apply_stage_attributes(stage, attrs, index, cadence)
    probability, stalled_after_days = cadence
    stage.position = index
    stage.is_won = attrs[:is_won]
    stage.is_lost = attrs[:is_lost]
    stage.label = attrs[:label]
    stage.color = attrs[:color]
    stage.probability = probability
    stage.stalled_after_days = stalled_after_days
  end

  def reconcile_stage(stage, attrs, cadence)
    probability, stalled_after_days = cadence
    stage.update!(label: attrs[:label]) if stage.label != attrs[:label]
    stage.update!(color: attrs[:color]) if stage.color != attrs[:color]
    stage.update!(probability: probability) if stage.probability != probability
    stage.update!(stalled_after_days: stalled_after_days) if stage.stalled_after_days != stalled_after_days
  end

  def seed_lost_reasons
    LOST_REASONS.each_with_index do |name, i|
      @account.lost_reasons.find_or_create_by!(name: name) { |r| r.position = i }
    end
  end

  def seed_benefits
    BENEFITS.each_with_index do |name, i|
      @account.benefit_types.find_or_create_by!(name: name) { |b| b.position = i }
    end
  end

  def seed_priorities
    PRIORITIES.each_with_index do |attrs, i|
      @account.lead_priorities.find_or_create_by!(name: attrs[:name]) do |p|
        p.weight = attrs[:weight]
        p.position = i
      end
    end
  end

  def seed_theses
    unless File.exist?(THESES_SEED_PATH)
      Rails.logger.warn('theses_seed.yml ausente — seed de teses pulado')
      return
    end

    YAML.safe_load_file(THESES_SEED_PATH)['theses'].each do |thesis_attrs|
      thesis = @account.theses.find_or_create_by!(name: thesis_attrs['name']) do |t|
        t.description = thesis_attrs['description']
        t.area = thesis_attrs['area']
        t.position = thesis_attrs['position']
      end
      seed_thesis_items(thesis, thesis_attrs['items'] || [])
    end
  end

  def seed_thesis_items(thesis, items)
    items.each do |item_attrs|
      thesis.thesis_items.find_or_create_by!(section: item_attrs['section'], title: item_attrs['title']) do |i|
        i.content = item_attrs['content']
        i.position = item_attrs['position']
      end
    end
  end

  def seed_triage_agents
    # tabela nasce na 20260703000003; mesmo guard das colunas de cadência
    return unless TriageAgent.table_exists?
    return unless File.exist?(TRIAGE_AGENTS_SEED_PATH)

    YAML.safe_load_file(TRIAGE_AGENTS_SEED_PATH)['agents'].each do |attrs|
      @account.triage_agents.find_or_create_by!(name: attrs['name']) do |agent|
        agent.assign_attributes(attrs.except('name'))
      end
    end
  end
end
