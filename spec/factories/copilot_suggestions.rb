FactoryBot.define do
  factory :copilot_suggestion do
    account
    lead { association :lead, account: account }
    kind { 'draft' }
    status { 'pending' }
    run_at { Time.current }
    payload { { 'tipo' => 'draft', 'texto' => 'Oi, tudo bem?', 'justificativa' => 'Lead parado' } }
  end
end
