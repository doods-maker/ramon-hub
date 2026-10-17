# Integração com a API de Conversões da Meta (Graph API). Erros e base URL ficam aqui: o cliente e o insights usam os dois.
module Ramon::MetaCapi
  VERSAO = 'v24.0'.freeze

  # 429, 5xx e rede: o job tenta de novo
  class Transitorio < StandardError; end

  # Outro 4xx: nova tentativa não resolve. Só código HTTP e error.code, nunca o corpo.
  class Recusado < StandardError
    attr_reader :http, :codigo

    def initialize(http, codigo = nil)
      @http = http
      @codigo = codigo
      super("Meta CAPI recusou: HTTP #{http}, code #{codigo || '-'}")
    end
  end

  # Lido na chamada (não em constante) para o ENV poder mudar em teste.
  def self.base
    "#{ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')}/#{VERSAO}"
  end
end
