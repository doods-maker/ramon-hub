# Petição a protocolar à mão no tribunal (Peticionamento · Fase 1): pacote de PDFs + registro do protocolo.
class Peticao < ApplicationRecord
  self.table_name = 'ramon_peticoes'

  STATUS = %w[conferencia rascunho protocolada].freeze
  ZONA = 'America/Sao_Paulo'.freeze
  PRAZO_PERTO_DIAS_UTEIS = 2
  LEITURA_BLOQUEADA = { 'lendo' => :leitura_em_andamento, 'erro' => :leitura_com_erro }.freeze
  CAMPOS_CONFERIDOS = %w[numero_processo contact_id tribunal].freeze

  belongs_to :account
  belongs_to :criado_por, class_name: 'User'
  belongs_to :responsavel, class_name: 'User'
  belongs_to :contact, optional: true
  belongs_to :protocolada_por, class_name: 'User', optional: true
  has_many :arquivos, -> { order(:posicao) }, class_name: 'PeticaoArquivo', inverse_of: :peticao, dependent: :destroy
  has_one_attached :comprovante

  before_validation :normalizar_numero
  # Antes do `audited`: a volta à conferência precisa entrar no registro de ações.
  before_update :reabrir_se_mudou_conferido

  # Registro de ações (o conteúdo dos PDFs fica de fora).
  AUDITADOS = %w[status numero_processo tribunal responsavel_id prazo numero_evento protocolada_em protocolada_por_id arquivada_em
                 executor].freeze
  audited only: AUDITADOS, associated_with: :account

  validates :tribunal, inclusion: { in: Ramon::Peticionamento::Tribunais::TODOS.keys }, unless: :conferencia?
  validates :status, inclusion: { in: STATUS }
  validates :numero_processo, presence: true, unless: -> { inicial? || conferencia? }
  validate :numero_processo_valido, unless: -> { inicial? || conferencia? }
  validates :drive_pasta_id, uniqueness: { scope: :account_id }, if: :pela_pasta?

  def protocolada? = status == 'protocolada'

  def conferencia? = status == 'conferencia'

  def editavel? = !protocolada?

  # Chaves i18n do backend; vazio = pode protocolar.
  def problemas
    lista = arquivos.to_a
    return ['sem_arquivos'] if lista.empty?

    limite = Ramon::Peticionamento::Tribunais::TODOS.dig(tribunal, :limite_bytes).to_i
    principais = lista.count(&:principal)
    out = []
    out << 'sem_principal' if principais.zero?
    out << 'varias_principais' if principais > 1
    out + acima_do_limite(lista, limite)
  end

  # Vence em até 2 dias úteis (seg–sex) a partir de hoje; vencido também conta.
  def prazo_perto?
    return false if prazo.blank?

    limite = Time.find_zone!(ZONA).today
    PRAZO_PERTO_DIAS_UTEIS.times do
      limite += 1
      limite += 1 while limite.saturday? || limite.sunday?
    end
    prazo <= limite
  end

  # Conferência -> rascunho: travas da leitura, do pacote e dos alertas; depois exige tribunal e número válidos.
  def confirmar!(confirmar_alertas: false)
    with_lock do # recarrega: as travas olham o estado gravado
      bloqueio = confirmar_bloqueado(confirmar_alertas)
      if bloqueio
        errors.add(:base, bloqueio)
        raise ActiveRecord::RecordInvalid, self
      end

      self.status = 'rascunho'
      save!
    end
  rescue ActiveRecord::RecordInvalid
    restore_attributes(['status'])
    raise
  end

  # Rascunho da pasta cuja principal mudou: confere de novo (a leitura segue `lida`, então o confirmar volta a valer).
  def reabrir_conferencia!
    with_lock { update!(status: 'conferencia') if rascunho_da_pasta? }
  end

  def registrar_protocolo!(usuario:, numero_evento:, comprovante:)
    with_lock do
      erro = protocolo_bloqueado(numero_evento, comprovante)
      if erro
        errors.add(:base, erro)
        raise ActiveRecord::RecordInvalid, self
      end

      # Sobe o comprovante antes: `attach` de arquivo só envia depois do commit, e storage fora deixaria protocolada sem comprovante.
      blob = ActiveStorage::Blob.create_and_upload!(io: comprovante, filename: comprovante.original_filename,
                                                    content_type: comprovante.content_type)
      update!(status: 'protocolada', numero_evento: numero_evento, protocolada_em: Time.current, protocolada_por: usuario)
      self.comprovante.attach(blob)
    end
    Ramon::PeticaoArquivarJob.perform_later(id)
  end

  def as_json_hub
    tribunal_info = Ramon::Peticionamento::Tribunais::TODOS[tribunal] || {}
    attributes.symbolize_keys.slice(:id, :numero_processo, :tribunal, :inicial, :prazo, :descricao, :status, :executor,
                                    :numero_evento, :protocolada_em, :arquivada_em, :drive_pasta_id, :drive_pasta_base_id,
                                    :pela_pasta, :leitura)
              .merge(tribunal_nome: tribunal_info[:nome], sistema: tribunal_info[:sistema], prazo_perto: prazo_perto?,
                     problemas: problemas, arquivos: arquivos.map(&:as_json_hub), comprovante_url: comprovante_url,
                     contato: contact && { id: contact.id, name: contact.name }, responsavel: pessoa(responsavel),
                     criado_por: pessoa(criado_por))
  end

  private

  # Sem tribunal ainda (conferência) o limite é 0: não há o que acusar.
  def acima_do_limite(lista, limite)
    return [] if limite.zero?

    lista.select { |a| a.tamanho > limite }.map { |a| "acima_do_limite:#{a.id}" }
  end

  def pessoa(usuario) = { id: usuario.id, name: usuario.name }

  def rascunho_da_pasta? = pela_pasta? && status == 'rascunho'

  # Roda depois da validação e da normalização: reenviar o mesmo número ou tribunal vazio não conta como mudança.
  def reabrir_se_mudou_conferido
    self.status = 'conferencia' if rascunho_da_pasta? && !status_changed? && changed.intersect?(CAMPOS_CONFERIDOS)
  end

  # Chave i18n do primeiro motivo para não confirmar; nil = pode.
  def confirmar_bloqueado(confirmar_alertas)
    return :fora_da_conferencia unless conferencia?
    return LEITURA_BLOQUEADA.fetch(leitura['estado'], :leitura_em_andamento) unless leitura['estado'] == 'lida'
    return :recusa_na_leitura if Array(leitura['recusas']).any?
    return :pacote_com_problemas if problemas.any?
    return :marcador_na_principal if marcador_na_principal?

    :alertas_nao_confirmados if alertas_sem_confirmar?(confirmar_alertas)
  end

  def alertas_sem_confirmar?(confirmar_alertas) = !confirmar_alertas && Ramon::Peticionamento::AlertasDaPasta.call(self)[:alertas].any?

  # A principal pode ter sido trocada na conferência: confere o PDF que está no pacote agora. Só vale para petição da pasta.
  def marcador_na_principal?
    arquivo = arquivos.find(&:principal) if pela_pasta?
    return false unless arquivo&.file&.attached?

    texto = arquivo.file.open { |io| Ramon::Peticionamento::MarcadoresRascunho.texto_do_pdf(io.read) }
    Ramon::Peticionamento::MarcadoresRascunho.no_texto(texto).any?
  end

  # Anti-objetivo da spec: nada vira "protocolada" sem número do evento e comprovante (arquivo de verdade, não "").
  def protocolo_bloqueado(numero_evento, comprovante)
    return :em_conferencia if conferencia?
    return :ja_protocolada if protocolada?
    return :sem_comprovante unless numero_evento.present? && comprovante.respond_to?(:read)

    return :pacote_com_problemas if problemas.any?

    :marcador_na_principal if marcador_na_principal?
  end

  def comprovante_url
    return unless comprovante.attached?

    ActiveStorage::Current.url_options = Rails.application.routes.default_url_options if ActiveStorage::Current.url_options.blank?
    Rails.application.routes.url_helpers.rails_blob_url(comprovante, disposition: 'attachment')
  end

  def normalizar_numero
    self.numero_processo = nil if numero_processo.blank?
    self.numero_processo = Ramon::Peticionamento::Cnj.normalizar(numero_processo) || numero_processo if numero_processo.present?
    self.tribunal = Ramon::Peticionamento::Cnj.tribunal(numero_processo) if tribunal.blank?
  end

  def numero_processo_valido
    errors.add(:numero_processo, :invalid) if numero_processo.present? && !Ramon::Peticionamento::Cnj.valido?(numero_processo)
  end
end
