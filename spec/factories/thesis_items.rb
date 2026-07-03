FactoryBot.define do
  factory :thesis_item do
    thesis
    section { 'abertura' }
    sequence(:title) { |n| "Item #{n}" }
    content { 'Conteúdo de exemplo do item de playbook.' }
    position { 0 }
  end
end
