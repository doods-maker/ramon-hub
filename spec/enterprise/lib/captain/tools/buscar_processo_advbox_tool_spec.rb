require 'rails_helper'

RSpec.describe Captain::Tools::BuscarProcessoAdvboxTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }

  # Formato REAL da resposta, conferido contra a API do AdvBox em 25/07: um envelope,
  # nunca um Array. Os mocks anteriores devolviam Array e por isso nao pegavam o bug
  # da busca vazia (Hash com data: [] nao e blank?).
  def envelope(itens)
    { 'offset' => 0, 'limit' => 10, 'totalCount' => itens.size, 'data' => itens, 'query' => {} }
  end

  describe '#perform' do
    it 'busca por cpf e devolve so a lista de processos, sem o envelope' do
      allow(Ramon::AdvboxClient).to receive(:lawsuits)
        .with(identification: '52998224725', limit: 10)
        .and_return(envelope([{ 'id' => 42, 'process_number' => '5001234-56.2026.4.04.7200' }]))

      result = tool.perform(tool_context, cpf: '529.982.247-25')
      parsed = JSON.parse(result)

      expect(parsed).to be_an(Array)
      expect(parsed.first['id']).to eq(42)
      expect(result).not_to include('totalCount')
    end

    it 'avisa que nao encontrou quando o envelope vem com data vazio' do
      allow(Ramon::AdvboxClient).to receive(:lawsuits)
        .with(name: 'Maria', limit: 10)
        .and_return(envelope([]))

      expect(tool.perform(tool_context, nome: 'Maria')).to eq('Nenhum processo encontrado no AdvBox.')
    end

    it 'aceita resposta em array puro, se a api mudar de formato' do
      allow(Ramon::AdvboxClient).to receive(:lawsuits)
        .with(name: 'Maria', limit: 10)
        .and_return([{ 'id' => 7 }])

      expect(JSON.parse(tool.perform(tool_context, nome: 'Maria')).first['id']).to eq(7)
    end

    it 'exige ao menos um criterio' do
      expect(tool.perform(tool_context)).to eq('Informe o nome, o CPF ou o numero do processo para buscar.')
    end

    it 'ignora cpf sem nenhum digito, tratando como criterio ausente' do
      expect(tool.perform(tool_context, cpf: 'nao sei')).to eq('Informe o nome, o CPF ou o numero do processo para buscar.')
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
