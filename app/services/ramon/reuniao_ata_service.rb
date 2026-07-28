# Transcreve o áudio da reunião no faster-whisper local e gera a ata via LLM.
# Transcrição já feita é reaproveitada (Reprocessar após falha do LLM não paga
# o whisper de novo). Erros sobem pro job marcar status=erro.
class Ramon::ReuniaoAtaService
  # Mesmo destino do Messages::AudioTranscriptionService (PR #106). O whisper
  # local ignora o access_token — nenhuma credencial de chat entra aqui.
  WHISPER_ENDPOINT = 'http://whisper:8000/'.freeze
  WHISPER_MODEL = 'Systran/faster-whisper-medium'.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o secretário de um escritório de advocacia previdenciária.
    Recebe a transcrição bruta de uma reunião presencial e redige a ATA em
    português do Brasil, em markdown, EXATAMENTE nesta estrutura:

    ## Resumo
    (um parágrafo com o essencial da reunião)

    ## Decisões
    - (uma decisão por linha; se nenhuma, escreva "Nenhuma decisão registrada.")

    ## Pendências
    - (uma por linha, "Ação — responsável — prazo"; responsável e prazo só
      quando citados; se nenhuma, escreva "Nenhuma pendência.")

    Não invente nada que não esteja na transcrição. Não use JSON nem cerca de
    código — só o markdown acima.
  PROMPT

  def initialize(reuniao)
    @reuniao = reuniao
  end

  def perform
    transcricao = @reuniao.transcricao.presence || transcrever
    @reuniao.update!(transcricao: transcricao)
    ata = gerar_ata(transcricao)
    @reuniao.update!(ata: ata, status: 'pronta', erro: nil)
  end

  private

  def transcrever
    @reuniao.audio.blob.open do |file|
      # temperature 0.0 evita alucinação em silêncio (mesma calibração do
      # serviço de mensagens).
      response = client.audio.transcribe(
        parameters: { model: whisper_model, file: file, temperature: 0.0 }
      )
      response['text'].to_s
    end
  end

  def client
    # Default do gem é 120s; reunião de 30–60min em CPU passa disso de longe.
    OpenAI::Client.new(
      access_token: 'local-whisper', uri_base: whisper_endpoint, log_errors: false,
      request_timeout: ENV.fetch('RAMON_WHISPER_TIMEOUT', 3600).to_i
    )
  end

  def whisper_endpoint
    ENV.fetch('RAMON_WHISPER_ENDPOINT', nil).presence || WHISPER_ENDPOINT
  end

  def whisper_model
    ENV.fetch('RAMON_WHISPER_MODEL', nil).presence || WHISPER_MODEL
  end

  # Conteúdo de reunião é sensível por definição; o deepseek está autorizado
  # na VPS via RAMON_LLM_SENSITIVE_OK_PROVIDERS (decisão do Eduardo 20/07).
  def gerar_ata(transcricao)
    Ramon::LlmClient.complete(
      provider: ENV.fetch('RAMON_REUNIAO_PROVIDER', 'deepseek'),
      model: ENV.fetch('RAMON_REUNIAO_MODEL', 'deepseek-chat'),
      system: SYSTEM_PROMPT, user: transcricao, sensitive: true
    ).content
  end
end
