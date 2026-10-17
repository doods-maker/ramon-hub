# Aviso de conversão à Meta: um por lead e evento (índice único). Ver Ramon::MetaConversoes.
class MetaEvento < ApplicationRecord
  self.table_name = 'ramon_meta_eventos'

  EVENTOS = %w[LeadSubmitted QualifiedLead InitiateCheckout Purchase].freeze
  STATUS = %w[pendente enviado erro ignorado].freeze

  belongs_to :account
  belongs_to :lead

  validates :evento, inclusion: { in: EVENTOS }
  validates :status, inclusion: { in: STATUS }
end
