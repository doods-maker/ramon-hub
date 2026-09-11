# Conta do Painel do Cliente (cliente.ramonantonio.adv.br): 1 linha por cliente
# do ADVBOX convidado. `processos` é o espelho JSON do ADVBOX (refeito à noite
# pelo Ramon::PortalSyncJob); `recados` = { lawsuit_id => texto } escrito no hub.
# Login = CPF + senha (provisória de 6 dígitos gerada no hub, trocável pelo
# cliente). E-mail é opcional: serve só pro convite e pro "esqueci a senha"
# (código de 6 dígitos). O cookie é a sessão.
class PortalCliente < ApplicationRecord
  CODIGO_VALIDADE = 10.minutes
  INTERVALO_ATUALIZACAO = 6.hours
  REGRA_SENHA = /\A\d{6,}\z/ # ponytail: só dígitos, mín. 6 — tipo senha de banco (decisão Eduardo 11/09)

  has_secure_password :senha, validations: false

  belongs_to :account
  has_many :assinaturas, class_name: 'PortalAssinatura', dependent: :destroy
  has_many :envios, class_name: 'PortalEnvio', dependent: :destroy

  before_validation :normalizar

  validates :nome, :cpf, :advbox_customer_id, presence: true
  validates :cpf, uniqueness: { scope: :account_id }
  validates :email, uniqueness: { scope: :account_id }, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :advbox_customer_id, uniqueness: { scope: :account_id }
  validates :senha, format: { with: REGRA_SENHA, message: 'precisa ter pelo menos 6 números' }, allow_nil: true

  # ponytail: escopado por account_id só porque é o índice único do banco; fork é
  # single-tenant (1 conta só) então na prática CPF/e-mail já são únicos globais.
  def self.from_cpf(cpf)
    digitos = cpf.to_s.delete('^0-9')
    digitos.present? ? find_by(cpf: digitos) : nil
  end

  def self.from_email(email)
    find_by(email: email&.downcase)
  end

  def gerar_senha_provisoria!
    senha = format('%06d', SecureRandom.random_number(1_000_000))
    update!(senha: senha)
    senha
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
    self.email = email.to_s.strip.downcase.presence
    self.cpf = cpf.to_s.delete('^0-9').presence
  end

  # SHA256 com o secret_key_base basta: código de 10 min + throttle no rack_attack.
  def digest(codigo)
    Digest::SHA256.hexdigest("#{codigo}#{Rails.application.secret_key_base}")
  end
end
