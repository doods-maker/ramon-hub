require 'rails_helper'

# Casos de teste da IA: com source 'teste' no estado, so as consultas rodam.
# Escrita (interna, sugestao, rascunho, AdvBox, HTTP personalizada) devolve o
# que faria e nao toca em nada.
RSpec.describe Captain::Tools::BasePublicTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:teste) { Struct.new(:state).new({ source: 'teste' }) }
  let(:stage) { create(:lead_stage, account: account, name: 'Qualificado', position: 1) }
  let(:lead) { create(:lead, account: account, lead_stage: stage, name: 'Maria', dcb_em: 1.year.ago.to_date) }

  def ferramenta(id)
    Captain::Assistant.resolve_tool_class(id).new(assistant)
  end

  it 'nenhuma ferramenta que nao e consulta executa em modo teste' do
    escritas = Captain::Assistant.built_in_agent_tools.reject { |tool| tool[:nivel] == 'consulta' }.pluck(:id)
    expect(escritas).to include('registrar_qualificacao', 'criar_tarefa_esteira', 'mover_etapa', 'criar_tarefa_advbox', 'handoff')

    escritas.each do |id|
      tool = ferramenta(id)
      expect(tool).not_to receive(:perform)
      expect(tool.execute(teste, lead_id: lead.id.to_s)).to start_with("[TESTE] faria #{id}(")
    end
  end

  it 'registrar_qualificacao, criar_tarefa_esteira e mover_etapa nao gravam nada', :aggregate_failures do
    attrs = lead.reload.custom_attributes

    ferramenta('registrar_qualificacao').execute(teste, lead_id: lead.id.to_s, criterio: 'sequela', status: 'ok')
    ferramenta('criar_tarefa_esteira').execute(teste, lead_id: lead.id.to_s, titulo: 'Cobrar CNIS', quando: '2030-01-10')
    saida = ferramenta('mover_etapa').execute(teste, lead_id: lead.id.to_s, etapa: 'Ganho')

    expect(saida).to eq("[TESTE] faria mover_etapa(lead_id: #{lead.id}, etapa: Ganho)")
    expect(lead.reload.custom_attributes).to eq(attrs)
    expect(lead.lead_tasks.count).to eq(0)
    expect(account.copilot_suggestions.count).to eq(0)
    expect(lead.lead_stage_id).to eq(stage.id)
  end

  it 'criar_tarefa_advbox com codigo nao chama o AdvBox' do
    expect(Ramon::AdvboxMcpService).not_to receive(:call_tool)

    saida = ferramenta('criar_tarefa_advbox').execute(teste, processo_id: '42', codigo: 'abc123')

    expect(saida).to start_with('[TESTE] faria criar_tarefa_advbox(')
  end

  it 'consulta roda normalmente e o registro sai marcado como teste' do
    saida = ferramenta('checar_prescricao').execute(teste, lead_id: lead.id.to_s)

    expect(saida).not_to include('[TESTE]')
    expect(Captain::ToolRun.last).to have_attributes(tool_name: 'checar_prescricao', source: 'teste', status: 'ok')
  end

  it 'fora do teste a escrita executa como sempre' do
    real = Struct.new(:state).new({ source: 'playground' })

    ferramenta('criar_tarefa_esteira').execute(real, lead_id: lead.id.to_s, titulo: 'Cobrar CNIS', quando: '2030-01-10')

    expect(lead.lead_tasks.count).to eq(1)
    expect(Captain::ToolRun.last.source).to eq('playground')
  end

  it 'HTTP personalizada nao faz a chamada em teste' do
    custom = create(:captain_custom_tool, account: account, http_method: 'POST', endpoint_url: 'https://example.com/orders')

    saida = Captain::Tools::HttpTool.new(assistant, custom).perform(teste, order_id: '123')

    expect(saida).to eq("[TESTE] faria #{custom.slug}(order_id: 123)")
    expect(WebMock).not_to have_requested(:post, 'https://example.com/orders')
  end

  it 'telas filtram o teste e mantem as linhas antigas sem source' do
    base = { account_id: account.id, tool_name: 'faq_lookup', status: 'ok' }
    antiga = Captain::ToolRun.create!(base)
    playground = Captain::ToolRun.create!(base.merge(source: 'playground'))
    Captain::ToolRun.create!(base.merge(source: 'teste'))

    expect(Captain::ToolRun.fora_de_teste).to contain_exactly(antiga, playground)
  end
end
