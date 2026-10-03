FactoryBot.define do
  factory :peca do
    account
    sequence(:slug) { |n| "0#{n}-peca-teste" }
    rodada { Date.new(2026, 10, 1) }
    tipo { 'carrossel' }
    gancho { 'Auxílio-acidente: quem tem direito' }
    conteudo { { 'fields' => { 'capa_titulo' => 'Título' }, 'legenda' => 'Legenda base', 'hashtags' => ['#inss', '#auxilioacidente'] } }
  end
end
