FactoryBot.define do
  factory :lead_stage do
    account
    sequence(:name) { |n| "Etapa #{n}" }
    position { 0 }
  end

  factory :benefit_type do
    account
    sequence(:name) { |n| "Benefício #{n}" }
  end

  factory :lead_priority do
    account
    sequence(:name) { |n| "Prioridade #{n}" }
    weight { 1 }
  end

  factory :lead do
    account
    lead_stage { association :lead_stage, account: account }
    name { 'Maria das Dores' }
  end
end
