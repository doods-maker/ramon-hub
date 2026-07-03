FactoryBot.define do
  factory :lost_reason do
    account
    sequence(:name) { |n| "Motivo #{n}" }
    position { 0 }
  end
end
