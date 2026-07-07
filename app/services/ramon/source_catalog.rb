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
end
