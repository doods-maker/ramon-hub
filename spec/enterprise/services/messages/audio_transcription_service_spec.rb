require 'rails_helper'

RSpec.describe Messages::AudioTranscriptionService, type: :service do
  let(:account) { create(:account, audio_transcriptions: true) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation) }
  let(:attachment) { message.attachments.create!(account: account, file_type: :audio) }

  before do
    # O base service exige a chave; endpoint e modelo são próprios do whisper (ver serviço)
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_API_KEY') { |config| config.value = 'test-api-key' }
  end

  describe 'transcription target' do
    let(:service) { described_class.new(attachment) }

    context 'when the Captain configs point to a chat LLM' do
      before do
        InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_MODEL') { |config| config.value = 'deepseek-v4-pro' }
        InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_ENDPOINT') { |config| config.value = 'https://api.openai.com/' }
      end

      it 'keeps talking to the local faster-whisper' do
        expect(service.model).to eq('Systran/faster-whisper-medium')
        expect(service.send(:uri_base)).to eq('http://whisper:8000/')
      end
    end

    context 'when the whisper envs are set' do
      it 'uses the endpoint and model from the envs' do
        with_modified_env RAMON_WHISPER_ENDPOINT: 'http://whisper-gpu:8000/', RAMON_WHISPER_MODEL: 'Systran/faster-whisper-large-v3' do
          expect(service.model).to eq('Systran/faster-whisper-large-v3')
          expect(service.send(:uri_base)).to eq('http://whisper-gpu:8000/')
        end
      end
    end
  end

  describe '#perform' do
    let(:service) { described_class.new(attachment) }

    context 'when transcription is successful' do
      before do
        # Mock can_transcribe? to return true and transcribe_audio method
        allow(service).to receive(:can_transcribe?).and_return(true)
        allow(service).to receive(:transcribe_audio).and_return('Hello world transcription')
      end

      it 'returns successful transcription' do
        result = service.perform
        expect(result).to eq({ success: true, transcriptions: 'Hello world transcription' })
      end
    end

    context 'when audio transcriptions are disabled' do
      before do
        account.update!(audio_transcriptions: false)
      end

      it 'returns error for transcription limit exceeded' do
        result = service.perform
        expect(result).to eq({ error: 'Transcription limit exceeded' })
      end
    end

    context 'when attachment already has transcribed text' do
      before do
        attachment.update!(meta: { transcribed_text: 'Existing transcription' })
        allow(service).to receive(:can_transcribe?).and_return(true)
      end

      it 'returns existing transcription without calling API' do
        result = service.perform
        expect(result).to eq({ success: true, transcriptions: 'Existing transcription' })
      end
    end

    context 'when the audio exceeds Whisper byte limit' do
      before do
        attachment.file.attach(
          io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
          filename: 'large.mp3',
          content_type: 'audio/mpeg'
        )
        allow(service).to receive(:can_transcribe?).and_return(true)
        allow(attachment.file.blob).to receive(:byte_size).and_return(described_class::TRANSCRIPTION_BYTE_LIMIT + 1)
      end

      it 'returns an error without calling Whisper' do
        expect(service).not_to receive(:transcribe_audio)
        expect(service.perform).to eq({ error: 'Audio too large for Whisper' })
      end
    end
  end

  describe '#update_transcription' do
    let(:service) { described_class.new(attachment) }

    it 'enfileira a extração da colheita quando a transcrição é gravada' do
      expect { service.send(:update_transcription, 'oi, sofri um acidente') }
        .to have_enqueued_job(Ramon::ColheitaExtractionJob).with(message.id)
    end

    it 'não enfileira nada com transcrição em branco' do
      expect { service.send(:update_transcription, '') }
        .not_to have_enqueued_job(Ramon::ColheitaExtractionJob)
    end
  end

  describe '#fetch_audio_file' do
    let(:service) { described_class.new(attachment) }

    before do
      attachment.file.attach(
        io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
        filename: 'speech',
        content_type: 'audio/mpeg'
      )
    end

    it 'adds extension from content type when filename has no extension' do
      temp_file_path = service.send(:fetch_audio_file)

      expect(File.extname(temp_file_path)).to eq('.mpeg')
    ensure
      FileUtils.rm_f(temp_file_path) if temp_file_path.present?
    end
  end
end
