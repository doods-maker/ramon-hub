# frozen_string_literal: true

# Converte o nome de uma etapa na etiqueta interna `fase-<slug>`, casando com a
# validação de título de Label do Chatwoot (\A[\p{L}\p{N}]+[\p{L}\p{N}_-]+\Z).
class Ramon::StageSlug
  PREFIX = 'fase-'

  def self.label_for(name)
    slug = I18n.transliterate(name.to_s.strip.downcase)
               .gsub(/[^a-z0-9]+/, '-')
               .gsub(/-+/, '-')
               .gsub(/\A-|-\z/, '')
    "#{PREFIX}#{slug}"
  end
end
