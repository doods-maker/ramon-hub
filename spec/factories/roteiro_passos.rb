FactoryBot.define do
  factory :roteiro_passo do
    account
    thesis { association :thesis, account: account }
    sequence(:chave) { |n| "passo_#{n}" }
    titulo { 'Passo' }
    tipo_resposta { 'sim_nao' }
    saidas { [] }
  end
end
