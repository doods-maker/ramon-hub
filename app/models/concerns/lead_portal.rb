# Portal do cliente (link mágico /portal/:token): o token é a credencial, vai no endereço e fica no histórico do
# WhatsApp — por isso tem validade (decisão 10/11/2026). Lead perdido perde o token (LeadDocs).
module LeadPortal
  extend ActiveSupport::Concern

  VALIDADE = 30.days
  CARIMBO = 'portal_token_em'.freeze

  # Token nasce sob demanda, nunca por callback. Gerar o link de novo renova o prazo; link vencido ganha token novo.
  def ensure_portal_token!
    carimbar_portal_token!(portal_token_valido? ? portal_token : SecureRandom.urlsafe_base64(24))
    portal_token
  end

  # Link de antes da validade (sem carimbo) vale: o prazo dele começa no primeiro acesso (Public::PortalController).
  def portal_token_valido?
    return false if portal_token.blank?

    gerado_em = Time.zone.parse(custom_attributes&.dig(CARIMBO).to_s)
    gerado_em.nil? || gerado_em > VALIDADE.ago
  end

  def portal_token_sem_prazo? = custom_attributes&.dig(CARIMBO).blank?

  # Direto no banco, só a chave do carimbo: sem callbacks do lead (o jsonb dispara exportação e avisos) e sem pisar em
  # escrita concorrente das outras chaves.
  def carimbar_portal_token!(token = portal_token)
    sql = "portal_token = ?, custom_attributes = jsonb_set(COALESCE(custom_attributes, '{}'::jsonb), '{#{CARIMBO}}', to_jsonb(?::text))"
    self.class.where(id: id).update_all([sql, token, Time.current.iso8601]) # rubocop:disable Rails/SkipsModelValidations
    reload
  end
end
