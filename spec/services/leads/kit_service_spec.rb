require 'rails_helper'

RSpec.describe Leads::KitService do
  let(:account) { create(:account) }
  let(:agent) { account.triage_agents.first } # seedado pelo create(:account)
  let(:lead) { create(:lead, account: account, name: 'João') }
  let(:triage) do
    lead.lead_triages.create!(account: account, triage_agent: agent, status: 'done',
                              viability: 'alta', result: 'Análise: caso viável pela Súmula 47.')
  end
  let(:service) { described_class.new(triage) }

  def kit_json
    {
      resumo_leigo: 'Caso bom.',
      roteiro_perguntas: ['Você se machucou no trabalho?'],
      documentos: [{ documento: 'CAT', porque: 'prova o acidente' }],
      venda_objecoes: { pitch: 'Vale a pena.', objecoes: [{ objecao: 'É caro?', resposta: 'Só paga no fim.' }] },
      proximo_passo: 'Assinar contrato.'
    }.to_json
  end

  it 'gera o kit e grava ready' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(kit_json)
    described_class.new(triage).perform
    triage.reload
    expect(triage.kit_status).to eq('ready')
    expect(triage.kit['resumo_leigo']).to eq('Caso bom.')
    expect(triage.kit['roteiro_perguntas']).to eq(['Você se machucou no trabalho?'])
    expect(triage.kit['documentos'].first['documento']).to eq('CAT')
    expect(triage.kit['venda_objecoes']['pitch']).to eq('Vale a pena.')
    expect(triage.kit['proximo_passo']).to eq('Assinar contrato.')
  end

  it 'monta o prompt do usuário com viabilidade e análise e repassa a trava LGPD' do
    expect(Ramon::LlmClient).to receive(:complete) do |provider:, model:, system:, user:, sensitive:|
      expect(provider).to eq('deepseek')
      expect(model).to eq('deepseek-chat')
      expect(system).to include('Kit do Closer')
      expect(user).to include('Viabilidade apurada: alta')
      expect(user).to include('Súmula 47')
      expect(sensitive).to be(false)
      kit_json
    end
    described_class.new(triage).perform
  end

  it 'pseudonimiza o nome do cliente no prompt (LGPD)' do
    expect(Ramon::LlmClient).to receive(:complete) do |user:, **|
      expect(user).to include('Cliente: [nome]')
      expect(user).not_to include('João')
      kit_json
    end
    described_class.new(triage).perform
  end

  it 'tolera cercas ```json e texto em volta' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return("Claro! Aqui está:\n```json\n#{kit_json}\n```\nEspero ter ajudado.")
    described_class.new(triage).perform
    expect(triage.reload.kit_status).to eq('ready')
  end

  it 'marca error quando a resposta não tem JSON utilizável' do
    allow(Ramon::LlmClient).to receive(:complete).and_return('não consigo')
    described_class.new(triage).perform
    triage.reload
    expect(triage.kit_status).to eq('error')
    expect(triage.kit['error']).to be_present
  end

  it 'marca error quando o JSON vem sem resumo_leigo' do
    allow(Ramon::LlmClient).to receive(:complete).and_return('{"roteiro_perguntas": []}')
    described_class.new(triage).perform
    expect(triage.reload.kit_status).to eq('error')
  end

  it 'marca error quando o LlmClient levanta exceção' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_raise(Ramon::LlmClient::MissingApiKeyError, 'ENV DEEPSEEK_API_KEY ausente')
    described_class.new(triage).perform
    triage.reload
    expect(triage.kit_status).to eq('error')
    expect(triage.kit['error']).to include('DEEPSEEK_API_KEY')
  end

  it 'includes prescription block when dcb_em is set' do
    lead.update!(dcb_em: Date.new(2020, 1, 15), benefit_monthly_value: 800)
    travel_to Date.new(2026, 7, 6) do
      prompt = service.send(:user_prompt)
      expect(prompt).to include('Prescricao (Art. 103')
      expect(prompt).to include('17 parcelas ja prescritas')
    end
  end

  it 'não sobrescreve status nem result da triagem' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(kit_json)
    described_class.new(triage).perform
    triage.reload
    expect(triage.status).to eq('done')
    expect(triage.result).to include('Súmula 47')
  end
end
