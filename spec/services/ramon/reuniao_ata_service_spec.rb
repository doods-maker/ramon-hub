require 'rails_helper'

RSpec.describe Ramon::ReuniaoAtaService do
  let(:account) { create(:account) }
  let(:reuniao) { create(:reuniao, account: account) }
  let(:llm_result) { Ramon::LlmClient::Result.new(content: '## Resumo', input_tokens: 1, output_tokens: 1) }

  before do
    reuniao.audio.attach(io: StringIO.new('fake-audio'), filename: 'reuniao.webm', content_type: 'audio/webm')
    stub_request(:post, 'http://whisper:8000/v1/audio/transcriptions')
      .to_return(status: 200, body: { text: 'fala transcrita' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result)
  end

  it 'transcreve, gera a ata e marca pronta' do
    described_class.new(reuniao).perform
    expect(reuniao.reload).to have_attributes(transcricao: 'fala transcrita', ata: '## Resumo', status: 'pronta')
    expect(Ramon::LlmClient).to have_received(:complete)
      .with(hash_including(user: 'fala transcrita', sensitive: true))
  end

  context 'when transcricao already exists' do
    it 'skips whisper and reuses it' do
      reuniao.update!(transcricao: 'ja transcrito')
      described_class.new(reuniao).perform
      expect(WebMock).not_to have_requested(:post, 'http://whisper:8000/v1/audio/transcriptions')
      expect(reuniao.reload.ata).to eq('## Resumo')
    end
  end
end
