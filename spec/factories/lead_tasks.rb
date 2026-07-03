FactoryBot.define do
  factory :lead_task do
    account
    lead { association :lead, account: account }
    title { 'Ligar para o cliente' }
    kind { 'follow_up' }
    due_at { 1.day.from_now }
  end
end
