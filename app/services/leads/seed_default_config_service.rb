class Leads::SeedDefaultConfigService
  STAGES = [
    { name: 'Novo', is_won: false, is_lost: false },
    { name: 'Qualificação', is_won: false, is_lost: false },
    { name: 'Reunião agendada', is_won: false, is_lost: false },
    { name: 'Reunião realizada', is_won: false, is_lost: false },
    { name: 'Negociação', is_won: false, is_lost: false },
    { name: 'Última chance', is_won: false, is_lost: false },
    { name: 'Fechado', is_won: true, is_lost: false },
    { name: 'Perdido', is_won: false, is_lost: true }
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
    STAGES.each_with_index do |attrs, i|
      @account.lead_stages.find_or_create_by!(name: attrs[:name]) do |s|
        s.position = i
        s.is_won = attrs[:is_won]
        s.is_lost = attrs[:is_lost]
      end
    end
    BENEFITS.each_with_index do |name, i|
      @account.benefit_types.find_or_create_by!(name: name) { |b| b.position = i }
    end
    PRIORITIES.each_with_index do |attrs, i|
      @account.lead_priorities.find_or_create_by!(name: attrs[:name]) do |p|
        p.weight = attrs[:weight]
        p.position = i
      end
    end
  end
end
