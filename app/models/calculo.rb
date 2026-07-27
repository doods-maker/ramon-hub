# Histórico de cálculos da tela Cálculos: um registro por cálculo que roda,
# com o CNIS já processado junto — fechar a janela não perde nada e reabrir
# volta ao estado exato sem reanexar o PDF.
class Calculo < ApplicationRecord
  belongs_to :account
  belongs_to :lead
  belongs_to :user, optional: true

  validates :tipo, presence: true

  scope :recentes, -> { order(created_at: :desc) }
  # Busca por cliente: nome do CNIS ou CPF (só dígitos, do jeito que se digita).
  scope :do_cliente, lambda { |termo|
    digitos = termo.gsub(/\D/, '')
    where('segurado_nome ILIKE :t OR segurado_cpf LIKE :d', t: "%#{termo}%", d: "%#{digitos.presence || termo}%")
  }

  def cnis_snapshot
    snapshot['cnis']
  end
end
