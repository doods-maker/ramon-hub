class ThesisItem < ApplicationRecord
  SECTIONS = %w[abertura apresentacao qualificacao objecao documento roteiro colheita].freeze

  belongs_to :thesis

  validates :section, presence: true, inclusion: { in: SECTIONS }
  validates :content, presence: true
  default_scope { order(:position) }
end
