class Messages::AudioTranscriptionService< Llm::LegacyBaseOpenAiService
  include Integrations::LlmInstrumentation

  # OpenAI's transcription endpoint hard limit is 25 MB *decimal* (25_000_000), not
  # binary (25.megabytes = 26_214_400) — using the binary form leaks the 25.0–26.2 MB
  # range to the API as 413s. Long audio (~70+ min Opus) keeps the attachment but skips
  # transcription.
  TRANSCRIPTION_BYTE_LIMIT = 25_000_000

  # ramon: destino da transcrição. Ver FORK-PONTO em #uri_base.
  WHISPER_ENDPOINT = 'http://whisper:8000/'.freeze
  WHISPER_MODEL = 'Systran/faster-whisper-medium'.freeze

  attr_reader :attachment, :message, :account

  def initialize(attachment)
    super()
    @attachment = attachment
    @message = attachment.message
    @account = message.account
  end

  def perform
    return { error: 'Transcription limit exceeded' } unless can_transcribe?
    return { error: 'Message not found' } if message.blank?
    return { error: 'Audio too large for Whisper' } if audio_too_large?

    transcriptions = transcribe_audio
    Rails.logger.info "Audio transcription successful: #{transcriptions}"
    { success: true, transcriptions: transcriptions }
  rescue Faraday::UnauthorizedError
    Rails.logger.warn('Skipping audio transcription: OpenAI configuration is invalid or disabled (401 Unauthorized).')
    { error: 'OpenAI configuration is invalid or disabled (401)' }
  end

  private

  # ramon: transcrição roda no nosso faster-whisper local (grátis), sem Captain/cota.
  # Interruptor por conta = account.audio_transcriptions.
  def can_transcribe?
    account.audio_transcriptions
  end

  # FORK-PONTO (ramon): o faster-whisper local NÃO é o provedor de chat do Captain.
  # Enquanto os dois dividiam as InstallationConfigs `CAPTAIN_OPEN_AI_*`, toda chamada
  # de CHAT do Captain (auto-resolver conversa, copiloto nativo, tradução de artigo,
  # tagline, Agents SDK) caía no container de transcrição — e mexer nelas pelo lado do
  # Captain quebrava a transcrição de áudio. Aqui a transcrição passa a ter endpoint e
  # modelo próprios; as `CAPTAIN_OPEN_AI_*` voltam a significar o que significam no
  # upstream. Calibráveis sem redeploy pelo chatwoot.env.
  # ponytail: a `CAPTAIN_OPEN_AI_API_KEY` continua compartilhada (o base monta o client
  # no initialize) — o speaches ignora o token, e a credencial real do chat do Captain
  # vem da `DEEPSEEK_API_KEY`. Separar também a chave só se ela virar segredo de verdade.
  def uri_base
    ENV.fetch('RAMON_WHISPER_ENDPOINT', nil).presence || WHISPER_ENDPOINT
  end

  def setup_model
    @model = ENV.fetch('RAMON_WHISPER_MODEL', nil).presence || WHISPER_MODEL
  end

  def audio_too_large?
    blob = attachment.file&.blob
    return false unless blob

    blob.byte_size > TRANSCRIPTION_BYTE_LIMIT
  end

  def fetch_audio_file
    blob = attachment.file.blob
    temp_dir = Rails.root.join('tmp/uploads/audio-transcriptions')
    FileUtils.mkdir_p(temp_dir)
    temp_file_name = "#{blob.key}-#{blob.filename}"

    if blob.filename.extension_without_delimiter.blank?
      extension = extension_from_content_type(blob.content_type)
      temp_file_name = "#{temp_file_name}.#{extension}" if extension.present?
    end

    temp_file_path = File.join(temp_dir, temp_file_name)

    File.open(temp_file_path, 'wb') do |file|
      blob.open do |blob_file|
        IO.copy_stream(blob_file, file)
      end
    end

    temp_file_path
  end

  def transcribe_audio
    transcribed_text = attachment.meta&.[]('transcribed_text') || ''
    return transcribed_text if transcribed_text.present?

    temp_file_path = fetch_audio_file
    transcribed_text = nil

    File.open(temp_file_path, 'rb') do |file|
      # temperature: 0.0 minimises hallucinations on silence / near-silent
      # audio; non-zero values trigger spiraling repeats — well-documented
      # behaviour across OpenAI transcription models.
      response = @client.audio.transcribe(
        parameters: {
          model: @model,
          file: file,
          temperature: 0.0
        }
      )
      transcribed_text = response['text']
    end

    update_transcription(transcribed_text)
    transcribed_text
  ensure
    FileUtils.rm_f(temp_file_path) if temp_file_path.present?
  end

  def instrumentation_params(file_path)
    {
      span_name: 'llm.messages.audio_transcription',
      model: @model,
      account_id: account&.id,
      feature_name: 'audio_transcription',
      file_path: file_path
    }
  end

  def update_transcription(transcribed_text)
    return if transcribed_text.blank?

    attachment.update!(meta: { transcribed_text: transcribed_text })
    message.reload.send_update_event
    # ramon: transcrição pronta → extração estruturada da colheita da reunião
    Ramon::ColheitaExtractionJob.perform_later(message.id)

    return unless ChatwootApp.advanced_search_allowed?

    message.reindex
  end

  def extension_from_content_type(content_type)
    subtype = content_type.to_s.downcase.split(';').first.to_s.split('/').last.to_s
    return if subtype.blank?

    {
      'x-m4a' => 'm4a',
      'x-wav' => 'wav',
      'x-mp3' => 'mp3'
    }.fetch(subtype, subtype)
  end
end
