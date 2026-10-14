class Thesis < ApplicationRecord
  belongs_to :account
  has_many :thesis_items, -> { order(:position) }, dependent: :destroy, inverse_of: :thesis
  has_many :leads, dependent: :nullify
  has_many :roteiro_passos, dependent: :destroy

  # Modelo do ZapSign do modo "sozinha até o contrato" (F3); vazio na tela = sem modelo.
  normalizes :zapsign_template_id, with: ->(v) { v.presence }

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :honorario_percentual,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
            allow_nil: true
  validates :honorario_n_mensalidades, :honorario_minimo_qtd,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_nil: true
  validates :honorario_minimo_base, inclusion: { in: %w[sm sb] }, allow_nil: true
  normalizes :honorario_minimo_base, with: ->(v) { v.presence }
  default_scope { order(:position) }
end
