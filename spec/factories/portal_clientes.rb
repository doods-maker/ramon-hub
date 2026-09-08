FactoryBot.define do
  factory :portal_cliente do
    account
    sequence(:advbox_customer_id) { |n| 14_000_000 + n }
    nome { 'Maria de Lourdes' }
    cpf { '12345678901' }
    sequence(:email) { |n| "cliente#{n}@exemplo.com" }
  end

  factory :portal_assinatura do
    portal_cliente
    sequence(:doc_token) { |n| "doc-#{n}" }
    sequence(:signer_token) { |n| "signer-#{n}" }
    nome { 'Procuração' }
  end

  factory :portal_envio do
    portal_cliente
    lawsuit_id { 14_039_119 }
    solicitacao_post_id { 270_197_305 }
    item { 'CNIS atualizado' }
  end
end
