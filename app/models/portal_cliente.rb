# Conta do Painel do Cliente (cliente.ramonantonio.adv.br): 1 linha por cliente
# do ADVBOX convidado. `processos` é o espelho JSON do ADVBOX (refeito à noite
# pelo Ramon::PortalSyncJob); `recados` = { lawsuit_id => texto } escrito no hub.
# Login = e-mail + código de 6 dígitos (sem senha); o cookie é a sessão.
class PortalCliente < ApplicationRecord
  CODIGO_VALIDADE = 10.minutes
  INTERVALO_ATUALIZACAO = 6.hours

  belongs_to :account
  has_many :assinaturas, class_name: 'PortalAssinatura', dependent: :destroy
  has_many :envios, class_name: 'PortalEnvio', dependent: :destroy

  before_validation :normalizar

  validates :nome, :email, :advbox_customer_id, presence: true
  validates :email, uniqueness: { scope: :account_id }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :advbox_customer_id, uniqueness: { scope: :account_id }

  def self.from_email(email)
    find_by(email: email&.downcase)
  end

  def gerar_codigo!
    codigo = format('%06d', SecureRandom.random_number(1_000_000))
    update!(codigo_digest: digest(codigo), codigo_expira_em: CODIGO_VALIDADE.from_now)
    codigo
  end

  def codigo_valido?(codigo)
    return false if codigo_digest.blank? || codigo_expira_em.blank? || codigo_expira_em.past?

    ActiveSupport::SecurityUtils.secure_compare(codigo_digest, digest(codigo.to_s.strip))
  end

  def consumir_codigo!
    update!(codigo_digest: nil, codigo_expira_em: nil)
  end

  def termos_aceitos? = termos_aceitos_em.present?

  def pode_atualizar?
    atualizacao_pedida_em.blank? || atualizacao_pedida_em < INTERVALO_ATUALIZACAO.ago
  end

  def processo(lawsuit_id)
    processos.find { |p| p['id'].to_s == lawsuit_id.to_s }
  end

  def primeiro_nome = nome.to_s.split.first.to_s.capitalize

  private

  def normalizar
    self.email = email.to_s.strip.downcase
    self.cpf = cpf.to_s.delete('^0-9').presence
  end

  # SHA256 com o secret_key_base basta: código de 10 min + throttle no rack_attack.
  def digest(codigo)
    Digest::SHA256.hexdigest("#{codigo}#{Rails.application.secret_key_base}")
  end
end
