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

  BENEFITS = ['Aposentadoria', 'BPC/LOAS', 'Auxílio-doença', 'Auxílio-acidente',
              'Pensão por morte', 'Trabalhista', 'Outro'].freeze

  PRIORITIES = [
    { name: 'Alta', weight: 3 },
    { name: 'Média', weight: 2 },
    { name: 'Baixa', weight: 1 }
  ].freeze

  def initialize(account)
    @account = account
  end

  def perform
    seed_stages
    seed_benefits
    seed_priorities
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
      stage = @account.lead_stages.find_or_create_by!(name: attrs[:name]) do |s|
        s.position = i
        s.is_won = attrs[:is_won]
        s.is_lost = attrs[:is_lost]
        s.label = attrs[:label]
        s.color = attrs[:color]
      end
      stage.update!(label: attrs[:label]) if stage.label != attrs[:label]
      stage.update!(color: attrs[:color]) if stage.color != attrs[:color]
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
end
