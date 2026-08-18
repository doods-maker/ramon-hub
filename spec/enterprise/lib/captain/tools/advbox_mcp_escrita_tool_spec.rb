require 'rails_helper'

RSpec.describe Captain::Tools::AdvboxMcpEscritaTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:tool) { Captain::Tools::CriarMovimentacaoAdvboxTool.new(assistant) }
  let(:dados) { { processo_id: '42', descricao: 'Peticao protocolada hoje', data: '2026-08-18' } }

  it 'so aceita as escritas permitidas e ganha o param codigo' do
    expect { Class.new(described_class) { mcp_tool 'advbox_criar_transacao' } }.to raise_error(ArgumentError, /permitida/)
    expect(Captain::Tools::CriarTarefaAdvboxTool.parameters.keys.map(&:to_s)).to include('codigo', 'processo_id', 'tipo_tarefa_id')
    expect(Captain::Tools::CriarClienteAdvboxTool.description).to include('NAO grava na primeira chamada')
    catalogo = YAML.load_file(Rails.root.join('config/agents/tools.yml')).pluck('id')
    expect(catalogo).to include('criar_tarefa_advbox', 'criar_movimentacao_advbox', 'criar_cliente_advbox', 'configuracoes_advbox')
  end

  it 'sem codigo devolve a previa e nao toca no AdvBox' do
    expect(Ramon::AdvboxClient).not_to receive(:create_movement)

    previa = tool.perform(tool_context, **dados)

    expect(previa).to start_with('NADA foi gravado ainda')
    expect(previa).to include('processo_id: 42', 'Peticao protocolada hoje')
    expect(previa).to match(/codigo=[0-9a-f]{6}\z/)
  end

  it 'com o codigo da previa grava; com codigo errado ou dados diferentes, recusa' do
    codigo = tool.perform(tool_context, **dados)[/codigo=(\h{6})/, 1]

    expect(tool.perform(tool_context, codigo: 'abcdef', **dados)).to include('nao confere')
    expect(tool.perform(tool_context, codigo: codigo, **dados.merge(descricao: 'Outra coisa mesmo'))).to include('nao confere')

    allow(Ramon::AdvboxClient).to receive(:create_movement)
      .with(lawsuit_id: 42, description: 'Peticao protocolada hoje', date: '18/08/2026')
      .and_return({ 'id' => 9 })
    expect(tool.perform(tool_context, codigo: codigo, **dados)).to eq('Gravado no AdvBox (advbox_criar_movimentacao): {"id":9}')
  end
end
