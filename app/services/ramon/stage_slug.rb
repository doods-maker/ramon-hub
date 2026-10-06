# frozen_string_literal: true

# Converte o nome de uma etapa na etiqueta interna `fase-<slug>`, casando com a
# validação de título de Label do Chatwoot (\A[\p{L}\p{N}]+[\p{L}\p{N}_-]+\Z).
class Ramon::StageSlug
  PREFIX = 'fase-'

  def self.label_for(name)
    slug = I18n.transliterate(name.to_s.strip.downcase)
               .gsub(/[^a-z0-9]+/, '-')
               .squeeze('-')
               .gsub(/\A-|-\z/, '')
    "#{PREFIX}#{slug}"
  end

  # O label é fixo desde a criação (renomear não muda): uma etapa nova com o
  # nome antigo de outra ganha sufixo (-2, -3…) em vez de colidir no índice único.
  def self.unique_label_for(account, name)
    base = label_for(name)
    label = base
    suffix = 1
    label = "#{base}-#{suffix += 1}" while account.lead_stages.exists?(label: label)
    label
  end
end
