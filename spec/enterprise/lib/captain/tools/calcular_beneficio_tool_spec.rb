require 'rails_helper'

RSpec.describe Captain::Tools::CalcularBeneficioTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:contact) { create(:contact, account: account, data_nascimento: '1980-05-10', sexo: 'M') }
  let(:lead) { create(:lead, account: account, contact: contact) }
  let(:resposta_motor) { { 'rmi' => '1200.00', 'valor_hoje' => '1500.00', 'avisos' => [] } }

  describe '#perform' do
    it 'estima pelo salario quando o caso nao tem cnis' do
      allow(Ramon::MotorClient).to receive(:incapacidade) do |payload|
        expect(payload[:competencias].size).to eq(12)
        expect(payload[:segurado][:nascimento]).to eq('1980-05-10')
        resposta_motor
      end

      resultado = JSON.parse(tool.perform(tool_context, lead_id: lead.id.to_s, der: '2026-01-10', salario: '3000'))

      expect(resultado['valor_mensal_hoje']).to eq('1500.00')
      expect(resultado['fonte']).to eq('salario informado')
    end

    it 'usa o cnis anexado quando existe, sem pedir salario' do
      lead.update!(cnis: { 'entrada' => { 'segurado' => { 'nascimento' => '1980-05-10', 'sexo' => 'M' },
                                          'competencias' => [{ 'ano' => 2025, 'mes' => 1, 'salario' => '2000.00' }] } })
      allow(Ramon::MotorClient).to receive(:incapacidade) do |payload|
        expect(payload[:competencias].size).to eq(1)
        resposta_motor
      end

      expect(JSON.parse(tool.perform(tool_context, lead_id: lead.id.to_s, der: '2026-01-10'))['fonte']).to eq('CNIS anexado')
    end

    it 'pede o salario quando nao ha cnis' do
      expect(Ramon::MotorClient).not_to receive(:incapacidade)

      expect(tool.perform(tool_context, lead_id: lead.id.to_s, der: '2026-01-10')).to include('Informe o salario')
    end

    it 'deduz a especie pela tese do caso' do
      lead.update!(thesis: create(:thesis, account: account, name: 'Auxílio-acidente'))
      allow(Ramon::MotorClient).to receive(:incapacidade) do |payload|
        expect(payload[:beneficio]).to eq('acidente')
        resposta_motor
      end

      tool.perform(tool_context, lead_id: lead.id.to_s, der: '2026-01-10', salario: '3000')
    end

    it 'devolve mensagem quando o motor recusa o calculo' do
      allow(Ramon::MotorClient).to receive(:incapacidade).and_raise(Ramon::MotorClient::ValidationError, 'der invalida')

      expect(tool.perform(tool_context, lead_id: lead.id.to_s, der: '2026-01-10', salario: '3000'))
        .to eq('O motor recusou o calculo: der invalida')
    end

    it 'devolve mensagem quando o motor esta fora do ar' do
      allow(Ramon::MotorClient).to receive(:incapacidade).and_raise(Ramon::MotorClient::UnavailableError)

      expect(tool.perform(tool_context, lead_id: lead.id.to_s, der: '2026-01-10', salario: '3000'))
        .to eq(described_class::MOTOR_FORA)
    end
  end
end
