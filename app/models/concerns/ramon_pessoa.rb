# Campos de pessoa do fork (Linha da Vida): cpf, data_nascimento, sexo.
# Extraído do Contact para não estourar o Metrics/ClassLength do modelo nativo.
module RamonPessoa
  extend ActiveSupport::Concern

  included do
    validates :cpf, allow_nil: true, uniqueness: { scope: [:account_id] }, cpf: true
    validates :sexo, allow_nil: true, inclusion: { in: %w[M F] }
    has_many :leads, dependent: :nullify

    # LGPD: trilha de auditoria (gem audited, tabela audits já existente no
    # schema) das mudanças em dados pessoais do titular. Limitada às colunas
    # de PII pra não inflar a tabela com last_activity_at e afins.
    audited only: %w[name email phone_number identifier cpf data_nascimento sexo blocked],
            associated_with: :account
  end

  private

  def prepare_cpf_attribute
    self.cpf = cpf.to_s.gsub(/\D/, '').presence if will_save_change_to_cpf?
  end
end
