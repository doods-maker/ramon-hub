# Peça de conteúdo do Instagram (carrossel/estático): pauta da rotina cloud →
# aprovação → montagem (worker na VPS) → agenda → publicação.
# Spec: docs/superpowers/specs/2026-10-02-conteudo-instagram-design.md
class Peca < ApplicationRecord
  self.table_name = 'ramon_pecas'

  STATUSES = %w[rascunho aprovado montando montado agendado publicando publicado reprovado falhou].freeze
  TIPOS = %w[carrossel estatico].freeze
  TRAVA = 15.minutes
  # Falha em que a Meta pode ter publicado sem devolver o id (textos de
  # Ramon::InstagramPublisher#publicar_container e PublicarPecasJob#interromper).
  AMBIGUA = /Pode ter ido ao ar|interrompida no meio/

  class TransicaoInvalida < StandardError; end

  belongs_to :account

  validates :slug, presence: true, uniqueness: { scope: :account_id }
  validates :gancho, :rodada, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :tipo, inclusion: { in: TIPOS }

  before_validation :legenda_inicial, on: :create
  after_update_commit :espelhar_notion, if: :saved_change_to_status?

  # Toda mudança de status passa por aqui: trava a linha e confere a origem, pra
  # tela, worker e cron nunca atropelarem um ao outro.
  def transicionar!(de:, para:, **attrs) # rubocop:disable Naming/MethodParameterName
    with_lock do
      raise TransicaoInvalida, "#{status} → #{para}" unless Array(de).include?(status)

      update!(status: para, **attrs)
    end
  end

  def publicacao_ambigua?
    status == 'falhou' && AMBIGUA.match?(erro.to_s)
  end

  def travada?
    status == 'montando' && montagem_iniciada_em.present? && montagem_iniciada_em < TRAVA.ago
  end

  private

  def legenda_inicial
    return if legenda.present?

    tags = Array(conteudo['hashtags']).join(' ')
    self.legenda = [conteudo['legenda'], tags.presence].compact.join("\n\n")
  end

  def espelhar_notion
    Ramon::NotionEspelhoJob.perform_later(id)
  end
end
