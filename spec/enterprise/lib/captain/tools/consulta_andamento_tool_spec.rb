require 'rails_helper'

RSpec.describe Captain::Tools::ConsultaAndamentoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:cpf) { '12345678909' }
  let(:cadastro) { { 'id' => 1, 'identification' => '123.456.789-09', 'birthdate' => '1980-05-10' } }
  let(:lawsuit) do
    { 'id' => 7, 'process_number' => '5001234-56.2026.4.04.7200', 'stage' => 'QUALQUER ETAPA DO ADVBOX', 'step' => 'JUDICIAL',
      'type' => 'AUXÍLIO-ACIDENTE - COMUM (B36)' }
  end

  before do
    allow(Ramon::AdvboxClient).to receive(:customers).with(identification: cpf).and_return({ 'data' => [cadastro] })
    allow(Ramon::AdvboxClient).to receive(:lawsuits).and_return({ 'data' => [lawsuit] })
    allow(Ramon::AdvboxClient).to receive_messages(movements: { 'data' => [] }, posts: { 'data' => [] })
  end

  it 'conta a audiencia marcada como o Painel mostra' do
    allow(Ramon::PortalSyncService).to receive(:agenda)
      .and_return([{ 'tipo' => 'audiencia', 'quando' => '2027-03-09 16:00:00', 'formato' => 'presencial' }])

    expect(tool.perform(tool_context, cpf: cpf)).to include('Compromisso marcado: Audiência em 09/03/2027 às 16h (presencial).')
  end

  it 'confere o CPF e devolve a fase do painel e o link' do
    create(:portal_cliente, account: account, cpf: cpf, convidado_em: 1.day.ago)

    with_modified_env PORTAL_URL: 'https://cliente.exemplo.br' do
      out = tool.perform(tool_context, cpf: '123.456.789-09')

      expect(out).to include('Auxílio-acidente', 'Justiça — Seu caso foi levado para um juiz decidir.')
      expect(out).to include('https://cliente.exemplo.br')
    end
  end

  it 'conferiu: o lead da conversa vai para Perdido "Já é cliente"' do
    create(:lead_stage, account: account, name: 'Perdido', position: 9, is_lost: true) unless account.lead_stages.exists?(is_lost: true)
    conversa = create(:conversation, account: account)
    lead = create(:lead, account: account, conversation: conversa)

    tool.perform(Struct.new(:state).new({ conversation: { id: conversa.id } }), cpf: cpf)

    expect(lead.reload.lost_reason).to eq('Já é cliente')
    expect(lead.lead_stage.is_lost).to be(true)
  end

  it 'CPF nao achado no AdvBox: nao conferiu e nao busca processo' do
    allow(Ramon::AdvboxClient).to receive(:customers).and_return({ 'data' => [] })
    expect(Ramon::AdvboxClient).not_to receive(:lawsuits)

    expect(tool.perform(tool_context, cpf: cpf)).to eq(described_class::NAO_CONFERIU)
  end

  it 'filtro do AdvBox casando CPF parecido: nao conferiu' do
    cadastro['identification'] = '123.456.789-00'

    expect(tool.perform(tool_context, cpf: cpf)).to eq(described_class::NAO_CONFERIU)
  end

  it '1a falha na conversa pede para conferir; da 2a em diante humano; a 4a nem consulta o AdvBox' do
    allow(Ramon::AdvboxClient).to receive(:customers).and_return({ 'data' => [] })
    conversa = create(:conversation, account: account)
    contexto = Struct.new(:state).new({ conversation: { id: conversa.id } })
    Redis::Alfred.delete("RAMON::CONSULTA_ANDAMENTO::FALHAS::#{conversa.id}")
    expect(tool.perform(contexto, cpf: cpf)).to eq(described_class::CONFERIR)
    2.times { expect(tool.perform(contexto, cpf: cpf)).to eq(described_class::NAO_CONFERIU) }

    expect(Ramon::AdvboxClient).not_to receive(:customers)
    expect(tool.perform(contexto, cpf: cpf)).to eq(described_class::LIMITE)
  end

  it 'nao grava o CPF na tela Execucoes' do
    tool.execute(tool_context, cpf: cpf)

    expect(Captain::ToolRun.last.params).to eq('cpf' => '[oculto]')
  end
end
