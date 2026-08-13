# frozen_string_literal: true

# Vocabulário fixo de canal (ponto de contato) do lead. `source` continua livre
# (qual campanha/LP/ad); `channel` é a dimensão controlada p/ atribuição/relatório.
class Ramon::SourceCatalog
  CHANNELS = [
    { key: 'meta_ads', label: 'Meta Ads' },
    { key: 'landing_page', label: 'Landing Page' },
    { key: 'instagram', label: 'Instagram' },
    { key: 'google_seo', label: 'Google/SEO' },
    { key: 'indicacao', label: 'Indicação' },
    { key: 'whatsapp_direto', label: 'WhatsApp direto' },
    { key: 'outro', label: 'Outro' }
  ].freeze

  # Regras de fallback/backfill p/ classificar `source` livre, primeira que casar.
  RULES = [
    [/\Aanuncio-meta/i, 'meta_ads'],
    [/indica/i, 'indicacao'],
    [/instagram|\big\b/i, 'instagram'],
    [/google|\bseo\b/i, 'google_seo']
  ].freeze

  # Assinaturas do texto pré-preenchido dos botões wa.me (1ª mensagem da conversa).
  # A mais específica vem primeiro: "site do escritório" (site institucional) tem
  # que vencer "vim pelo site e gostaria" (texto atual das LPs em produção —
  # mudar esses textos quebra a derivação; ver plano onda1-aquisicao-limpa).
  SIGNATURES = [
    [/vim pelo site do escrit[óo]rio/i, %w[google_seo site-institucional]],
    [/vim pelo site e gostaria/i, %w[landing_page lp:whatsapp]],
    [/fiz a triagem/i, %w[landing_page lp:triagem]],
    [/vim pelo instagram/i, %w[instagram instagram-bio]]
  ].freeze

  def self.labels
    @labels ||= CHANNELS.to_h { |c| [c[:key], c[:label]] }
  end

  def self.valid?(key)
    labels.key?(key.to_s)
  end

  def self.derive(source)
    return nil if source.blank?

    RULES.find { |pattern, _key| source.match?(pattern) }&.last
  end

  def self.derive_from_message(text)
    return nil if text.blank?

    SIGNATURES.find { |pattern, _result| text.match?(pattern) }&.last
  end
end
