FactoryBot.define do
  factory :thesis do
    account
    sequence(:name) { |n| "Tese #{n}" }
    area { 'previdenciario' }
    position { 0 }
  end
end
