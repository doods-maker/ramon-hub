# frozen_string_literal: true

namespace :ramon do
  namespace :teses do
    desc 'Aplica a etiqueta tese-* nas conversas dos leads que ja tem tese (idempotente; ' \
         'os leads novos/alterados ja sincronizam sozinhos). Uso: rake ramon:teses:etiquetas'
    task etiquetas: :environment do
      Lead.where.not(conversation_id: nil).where.not(thesis_id: nil).find_each do |lead|
        Ramon::TeseLabelSync.apply_to_conversation(lead)
      end
    end
  end
end
