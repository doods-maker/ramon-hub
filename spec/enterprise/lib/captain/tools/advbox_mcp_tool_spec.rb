require 'rails_helper'

RSpec.describe Captain::Tools::AdvboxMcpTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool_context) { Struct.new(:state).new({}) }

  let(:pontes) do
    {
      Captain::Tools::ProcessoAdvboxTool => 'advbox_processo',
      Captain::Tools::MovimentacoesAdvboxTool => 'advbox_movimentacoes',
      Captain::Tools::HistoricoTarefasAdvboxTool => 'advbox_historico_tarefas',
      Captain::Tools::UltimasMovimentacoesAdvboxTool => 'advbox_ultimas_movimentacoes',
      Captain::Tools::TarefasAdvboxTool => 'advbox_tarefas',
      Captain::Tools::BuscarClienteAdvboxTool => 'advbox_buscar_clientes',
      Captain::Tools::ClienteAdvboxTool => 'advbox_cliente',
      Captain::Tools::DocumentosAdvboxTool => 'advbox_documentos',
      Captain::Tools::LinkDocumentoAdvboxTool => 'advbox_documento_link'
    }
  end

  it 'espelha descricao e parametros da ferramenta MCP homonima, e todas estao no catalogo' do
    catalogo = YAML.load_file(Rails.root.join('config/agents/tools.yml')).pluck('id')
    pontes.each do |klass, mcp|
      schema = Ramon::AdvboxMcpService::TOOLS.find { |t| t[:name] == mcp }
      expect(klass.description).to eq(schema[:description])
      expect(klass.parameters.keys.map(&:to_s)).to match_array(schema[:inputSchema][:properties].keys.map(&:to_s))
      expect(catalogo).to include(klass.name.demodulize.delete_suffix('Tool').underscore)
    end
  end

  it 'recusa ferramenta de escrita' do
    expect { Class.new(described_class) { mcp_tool 'advbox_criar_tarefa' } }.to raise_error(ArgumentError, /grava/)
  end

  it 'coage inteiros vindos como string e devolve o json do MCP' do
    allow(Ramon::AdvboxClient).to receive(:movements).with(42, limit: 3).and_return([{ 'id' => 1 }])

    resultado = Captain::Tools::MovimentacoesAdvboxTool.new(assistant).perform(tool_context, processo_id: '42', limite: '3')

    expect(JSON.parse(resultado)).to eq([{ 'id' => 1 }])
  end

  it 'devolve o erro do MCP como texto quando falta argumento ou o AdvBox cai' do
    tool = Captain::Tools::ClienteAdvboxTool.new(assistant)
    expect(tool.perform(tool_context)).to start_with('Argumento inválido')

    allow(Ramon::AdvboxClient).to receive(:customer).and_raise(Ramon::AdvboxClient::UnavailableError, 'fora')
    expect(tool.perform(tool_context, id: 5)).to eq('fora')
  end
end
