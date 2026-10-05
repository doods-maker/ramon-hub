# Automação desenhada no quadro (spec automacoes-em-fluxo): 1 gatilho + passos.
# Edita-se o `rascunho`; publicar congela uma FluxoVersao — execuções em andamento
# seguem na versão em que começaram.
class Fluxo < ApplicationRecord
  self.table_name = 'ramon_fluxos'

  ORIGENS = %w[usuario convertido sistema].freeze
  MODOS = %w[normal sombra].freeze
  ZONA = 'America/Sao_Paulo'.freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :versao_publicada, class_name: 'FluxoVersao', optional: true
  has_many :versoes, class_name: 'FluxoVersao', dependent: :destroy_async
  has_many :execucoes, class_name: 'FluxoExecucao', dependent: :destroy_async

  validates :nome, presence: true
  validates :origem, inclusion: { in: ORIGENS }
  validates :modo, inclusion: { in: MODOS }
  validates :limite_dia, numericality: { greater_than: 0 }, allow_nil: true

  # Fluxo do sistema é só desenho (o código de hoje ainda roda) — o motor nunca executa.
  scope :executaveis, -> { where(ativo: true).where.not(origem: 'sistema').where.not(versao_publicada_id: nil) }

  def publicar!(user)
    grafo = Ramon::Fluxos::Grafo.new(rascunho)
    erros = grafo.erros
    raise Ramon::Fluxos::Grafo::Invalido, erros.join(' · ') if erros.any?

    transaction do
      versao = versoes.create!(numero: (versoes.maximum(:numero) || 0) + 1, grafo: rascunho, publicado_por_id: user&.id)
      update!(versao_publicada: versao, gatilho_tipo: grafo.gatilho.dig('config', 'tipo'))
      versao
    end
  end

  def execucoes_hoje = execucoes.where(ensaio: false, created_at: Time.find_zone!(ZONA).now.all_day)

  def limite_atingido? = limite_dia.present? && execucoes_hoje.count >= limite_dia

  # ponytail: contadores por fluxo (N consultas); agregar numa query se passar de ~50 fluxos.
  def resumo_json
    {
      id: id, nome: nome, descricao: descricao, gatilho_tipo: gatilho_tipo, ativo: ativo, limite_dia: limite_dia,
      origem: origem, sistema_chave: sistema_chave, modo: modo, versao: versao_publicada&.numero,
      editado_em: updated_at
    }.merge(contadores)
  end

  private

  def contadores
    vivas = execucoes.where(ensaio: false)
    {
      hoje: execucoes_hoje.count, esperando: vivas.where(status: 'esperando').count,
      falharam_24h: vivas.where(status: 'falhou', updated_at: 24.hours.ago..).count, ultima_em: vivas.maximum(:created_at)
    }
  end
end
