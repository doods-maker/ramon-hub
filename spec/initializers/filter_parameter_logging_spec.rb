require 'rails_helper'

RSpec.describe 'filter_parameters' do # rubocop:disable RSpec/DescribeClass
  it 'não deixa senha, código nem CPF do Painel do Cliente irem ao log' do
    filtro = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    entrada = { 'cpf' => '52998224725', 'senha' => '123456', 'senha_atual' => '1', 'confirmacao' => '2', 'codigo' => '999111', 'nome' => 'ok' }

    expect(filtro.filter(entrada)).to eq(entrada.transform_values { '[FILTERED]' }.merge('nome' => 'ok'))
  end
end
