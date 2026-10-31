# Petição a protocolar à mão no tribunal (Peticionamento · Fase 1): pacote de PDFs + registro do protocolo.
class Peticao < ApplicationRecord
  self.table_name = 'ramon_peticoes'

  STATUS = %w[rascunho protocolada].freeze
  ZONA = 'America/Sao_Paulo'.freeze
  PRAZO_PERTO_DIAS_UTEIS = 2

  belongs_to :account
  belongs_to :criado_por, class_name: 'User'
  belongs_to :responsavel, class_name: 'User'
  belongs_to :contact, optional: true
  belongs_to :protocolada_por, class_name: 'User', optional: true
  has_many :arquivos, -> { order(:posicao) }, class_name: 'PeticaoArquivo', inverse_of: :peticao, dependent: :destroy
  has_one_attached :comprovante

  # Registro de ações (o conteúdo dos PDFs fica de fora).
  AUDITADOS = %w[status numero_processo tribunal responsavel_id prazo numero_evento protocolada_em protocolada_por_id arquivada_em
                 executor].freeze
  audited only: AUDITADOS, associated_with: :account

  before_validation :normalizar_numero

  validates :tribunal, inclusion: { in: Ramon::Peticionamento::Tribunais::TODOS.keys }
  validates :status, inclusion: { in: STATUS }
  validates :numero_processo, presence: true, unless: :inicial?
  validate :numero_processo_valido, unless: :inicial?

  def protocolada? = status == 'protocolada'

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
    out + lista.select { |a| a.tamanho > limite }.map { |a| "acima_do_limite:#{a.id}" }
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

  def registrar_protocolo!(usuario:, numero_evento:, comprovante:)
    with_lock do
      erro = protocolo_bloqueado(numero_evento, comprovante)
      if erro
        errors.add(:base, erro)
        raise ActiveRecord::RecordInvalid, self
      end

      update!(status: 'protocolada', numero_evento: numero_evento, protocolada_em: Time.current, protocolada_por: usuario)
      self.comprovante.attach(comprovante)
    end
    Ramon::PeticaoArquivarJob.perform_later(id)
  end

  def as_json_hub
    tribunal_info = Ramon::Peticionamento::Tribunais::TODOS[tribunal] || {}
    attributes.symbolize_keys.slice(:id, :numero_processo, :tribunal, :inicial, :prazo, :descricao, :status, :executor,
                                    :numero_evento, :protocolada_em, :arquivada_em, :drive_pasta_id, :drive_pasta_base_id)
              .merge(tribunal_nome: tribunal_info[:nome], sistema: tribunal_info[:sistema], prazo_perto: prazo_perto?,
                     problemas: problemas, arquivos: arquivos.map(&:as_json_hub), comprovante_url: comprovante_url,
                     contato: contact && { id: contact.id, name: contact.name }, responsavel: pessoa(responsavel),
                     criado_por: pessoa(criado_por))
  end

  private

  def pessoa(usuario) = { id: usuario.id, name: usuario.name }

  # Anti-objetivo da spec: nada vira "protocolada" sem número do evento e comprovante (arquivo de verdade, não "").
  def protocolo_bloqueado(numero_evento, comprovante)
    return :ja_protocolada if protocolada?
    return :sem_comprovante unless numero_evento.present? && comprovante.respond_to?(:read)

    :pacote_com_problemas if problemas.any?
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
