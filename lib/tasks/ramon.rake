# frozen_string_literal: true

namespace :ramon do
  desc 'Garante as Labels fase-* (uma por etapa do funil) em todas as contas. ' \
       'As labels normalmente nascem sob demanda (StageLabelSync); este task as ' \
       'cria de uma vez para ficarem disponíveis no seletor de labels da conversa.'
  task ensure_fase_labels: :environment do
    Account.find_each do |account|
      account.lead_stages.where.not(label: [nil, '']).find_each do |stage|
        Ramon::StageLabelSync.ensure_label(account, stage.label)
      end
      count = account.labels.where('title LIKE ?', 'fase-%').count
      Rails.logger.info("[ramon:ensure_fase_labels] conta #{account.id}: #{count} labels fase-*")
    end
  end
end
