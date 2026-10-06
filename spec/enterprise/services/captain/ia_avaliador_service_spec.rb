require 'rails_helper'

RSpec.describe Captain::IaAvaliadorService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:resposta) { 'Você só paga se receber: 30% dos atrasados + 3 parcelas. Alguém da equipe vai te chamar.' }
  let(:saida) { { resposta: resposta, ferramentas: [{ nome: 'faq_lookup', resultado: 'ok' }], handoff: false } }

  def caso(criterios)
    Captain::IaCaso.create!(account: account, assistant: assistant, titulo: 'A5', criterios: criterios,
                            mensagens: [{ role: 'user', content: 'quanto vocês cobram?' }])
  end

  def avaliar(criterios, outra_saida = saida)
    described_class.new(caso(criterios), outra_saida).avaliar
  end

  it 'passa quando todas as regras fixas batem e nao chama o juiz sem rubrica' do
    expect(Ramon::LlmClient).not_to receive(:complete)

    resultado = avaliar('deve_usar' => ['faq_lookup'], 'nao_deve_usar' => ['mover_etapa'], 'handoff' => 'nao',
                        'deve_conter' => ['so paga se receber', '/30\s*%/'], 'nao_pode_conter' => ['desconto'])

    expect(resultado).to eq(passou: true, motivos: [])
  end

  it 'deve_usar e nao_deve_usar', :aggregate_failures do
    expect(avaliar('deve_usar' => ['playbook_da_tese'])[:motivos]).to eq(['Não usou playbook_da_tese'])
    expect(avaliar('nao_deve_usar' => ['faq_lookup'])[:motivos]).to eq(['Usou faq_lookup, que não devia'])
  end

  it 'handoff sim, nao e indiferente', :aggregate_failures do
    expect(avaliar('handoff' => 'sim')[:motivos]).to eq(['Não passou para humano'])
    expect(avaliar({ 'handoff' => 'nao' }, saida.merge(handoff: true))[:motivos]).to eq(['Passou para humano sem precisar'])
    expect(avaliar({ 'handoff' => 'indiferente' }, saida.merge(handoff: true))[:passou]).to be(true)
  end

  it 'deve_conter e nao_pode_conter aceitam frase sem acento/caixa e /regex/', :aggregate_failures do
    expect(avaliar('deve_conter' => ['ALGUÉM DA EQUIPE'])[:passou]).to be(true)
    expect(avaliar('deve_conter' => ['Tubarão'])[:motivos]).to eq(['Faltou: Tubarão'])
    expect(avaliar('nao_pode_conter' => ['/\d+\s*meses/'])[:passou]).to be(true)
    expect(avaliar('nao_pode_conter' => ['/\d+\s*parcelas/'])[:motivos]).to eq(['Disse o proibido: /\d+\s*parcelas/'])
    expect(avaliar('deve_conter' => ['/([/'])[:passou]).to be(false)
  end

  it 'com rubrica chama o juiz e usa o veredito', :aggregate_failures do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: '```json {"passou": false, "motivo": "prometeu prazo"} ```', input_tokens: 1,
                                               output_tokens: 1))

    expect(avaliar('rubrica' => 'Não promete prazo.')).to eq(passou: false, motivos: ['Juiz: prometeu prazo'])
    expect(Ramon::LlmClient).to have_received(:complete).with(hash_including(provider: 'deepseek', sensitive: true))
  end

  it 'juiz aprovando passa; juiz fora do ar reprova com motivo', :aggregate_failures do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: '{"passou": true, "motivo": "ok"}', input_tokens: 1, output_tokens: 1))
    expect(avaliar('rubrica' => 'Acolhe.')[:passou]).to be(true)

    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::MissingApiKeyError)
    expect(avaliar('rubrica' => 'Acolhe.')[:motivos].first).to start_with('Juiz indisponível')
  end

  it 'regra fixa falhando nao gasta o juiz' do
    expect(Ramon::LlmClient).not_to receive(:complete)

    expect(avaliar('deve_usar' => ['handoff'], 'rubrica' => 'Acolhe.')[:passou]).to be(false)
  end
end
