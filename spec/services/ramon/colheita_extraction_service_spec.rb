require 'rails_helper'

RSpec.describe Ramon::ColheitaExtractionService do
  let(:account) { create(:account) }
  let(:thesis) { account.theses.find_by!(name: 'Auxílio-acidente (B36)') }
  let(:conversation) { create(:conversation, account: account) }
  let(:lead) do
    create(:lead, account: account, name: 'João da Silva', thesis: thesis,
                  conversation: conversation, custom_attributes: { 'foo' => 'bar' })
  end

  def colheita_json
    {
      cliente: { profissao: 'montador industrial' },
      acidente: { data: '2023-08-14', tipo: 'trabalho', descricao: 'prensa pegou a mão' },
      beneficios: [{ especie: 'B91', situacao: 'cessado', dcb: '2024-02-28' }],
      confirmar: ['acidente.data'],
      lacunas: [{ campo: 'beneficios[0].nb', como_obter: 'carta de concessão — Meu INSS' }]
    }.to_json
  end

  def llm_result(content)
    Ramon::LlmClient::Result.new(content: content, input_tokens: 40, output_tokens: 20)
  end

  before do
    create(:message, conversation: conversation, account: account,
                     message_type: :incoming, content: 'Sofri um acidente, meu CPF é 123.456.789-00')
  end

  it 'grava a colheita extraída em custom_attributes preservando as outras chaves' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result(colheita_json))
    described_class.new(lead).perform
    lead.reload
    colheita = lead.custom_attributes['colheita']
    expect(lead.custom_attributes['foo']).to eq('bar')
    expect(colheita['dados']['acidente']['tipo']).to eq('trabalho')
    expect(colheita['lacunas']).to eq([{ 'campo' => 'beneficios[0].nb', 'como_obter' => 'carta de concessão — Meu INSS' }])
    expect(colheita['confirmar']).to eq(['acidente.data'])
    expect(colheita['mascarada']).to be(true)
  end

  it 'preenche dcb_em com a DCB do auxílio-doença cessado quando estava vazio' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result(colheita_json))
    described_class.new(lead).perform
    expect(lead.reload.dcb_em).to eq(Date.new(2024, 2, 28))
  end

  it 'não sobrescreve dcb_em preenchido por humano' do
    lead.update!(dcb_em: Date.new(2023, 1, 1))
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result(colheita_json))
    described_class.new(lead).perform
    expect(lead.reload.dcb_em).to eq(Date.new(2023, 1, 1))
  end

  it 'pseudonimiza o transcript por padrão (deepseek) e não liga a flag sensível' do
    expect(Ramon::LlmClient).to receive(:complete) do |provider:, user:, sensitive:, **|
      expect(provider).to eq('deepseek')
      expect(user).to include('[cpf]')
      expect(user).not_to include('123.456.789-00')
      expect(sensitive).to be(false)
      llm_result(colheita_json)
    end
    described_class.new(lead).perform
  end

  it 'manda o transcript íntegro com sensitive quando o provider autoriza dado pessoal' do
    with_modified_env RAMON_COLHEITA_PROVIDER: 'anthropic', RAMON_COLHEITA_MODEL: 'claude-sonnet-5' do
      expect(Ramon::LlmClient).to receive(:complete) do |provider:, user:, sensitive:, **|
        expect(provider).to eq('anthropic')
        expect(user).to include('123.456.789-00')
        expect(sensitive).to be(true)
        llm_result(colheita_json)
      end
      described_class.new(lead).perform
      expect(lead.reload.custom_attributes.dig('colheita', 'mascarada')).to be(false)
    end
  end

  it 'não chama o LLM quando a tese do lead não é auxílio-acidente' do
    other = account.theses.where.not(id: thesis.id).first
    lead.update!(thesis: other)
    expect(Ramon::LlmClient).not_to receive(:complete)
    described_class.new(lead).perform
  end

  it 'não chama o LLM quando o lead não tem conversa' do
    orphan = create(:lead, account: account, thesis: thesis)
    expect(Ramon::LlmClient).not_to receive(:complete)
    described_class.new(orphan).perform
  end

  it 'engole resposta sem JSON válido logando o erro, sem gravar nada' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('não consigo ajudar'))
    allow(Rails.logger).to receive(:error)
    described_class.new(lead).perform
    expect(Rails.logger).to have_received(:error).with(/ColheitaExtraction/)
    expect(lead.reload.custom_attributes).not_to have_key('colheita')
  end

  it 'repropaga TransientError para o retry do job' do
    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError, '429')
    expect { described_class.new(lead).perform }.to raise_error(Ramon::LlmClient::TransientError)
  end

  it 'aceita JSON com cercas de código e texto em volta' do
    raw = "Claro! Segue:\n```json\n#{colheita_json}\n```"
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result(raw))
    described_class.new(lead).perform
    expect(lead.reload.custom_attributes.dig('colheita', 'dados', 'cliente', 'profissao')).to eq('montador industrial')
  end
end
