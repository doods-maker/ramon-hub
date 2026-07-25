require 'rails_helper'

RSpec.describe Captain::Tools::BuscarProcessoAdvboxTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }

  describe '#perform' do
    it 'busca por cpf e devolve os processos em json' do
      allow(Ramon::AdvboxClient).to receive(:lawsuits)
        .with(identification: '52998224725', limit: 10)
        .and_return([{ 'id' => 42, 'process_number' => '5001234-56.2026.4.04.7200' }])

      result = tool.perform(tool_context, cpf: '529.982.247-25')

      expect(JSON.parse(result).first['id']).to eq(42)
    end

    it 'busca por nome quando nao ha cpf' do
      allow(Ramon::AdvboxClient).to receive(:lawsuits)
        .with(name: 'Maria', limit: 10)
        .and_return([])

      expect(tool.perform(tool_context, nome: 'Maria')).to eq('Nenhum processo encontrado no AdvBox.')
    end

    it 'exige ao menos um criterio' do
      expect(tool.perform(tool_context)).to eq('Informe o nome ou o CPF para buscar.')
    end

    it 'ignora cpf sem nenhum digito, tratando como criterio ausente' do
      expect(tool.perform(tool_context, cpf: 'nao sei')).to eq('Informe o nome ou o CPF para buscar.')
    end

    it 'devolve mensagem quando o advbox recusa' do
      allow(Ramon::AdvboxClient).to receive(:lawsuits)
        .and_raise(Ramon::AdvboxClient::RequestError.new(422, 'erro'))

      expect(tool.perform(tool_context, nome: 'Maria')).to eq('O AdvBox recusou a consulta (HTTP 422).')
    end

    it 'devolve mensagem quando o advbox esta fora do ar' do
      allow(Ramon::AdvboxClient).to receive(:lawsuits)
        .and_raise(Ramon::AdvboxClient::UnavailableError)

      expect(tool.perform(tool_context, nome: 'Maria')).to eq('O AdvBox nao respondeu agora. Tente de novo em instantes.')
    end
  end
end
