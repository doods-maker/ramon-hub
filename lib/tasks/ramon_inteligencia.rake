# frozen_string_literal: true

namespace :ramon do
  namespace :inteligencia do
    desc 'Seed idempotente da area Inteligencia (assistentes, skills e FAQ) numa conta. ' \
         'Uso: rake ramon:inteligencia:seed[account_id]'
    task :seed, [:account_id] => :environment do |_task, args|
      raise ArgumentError, 'Uso: rake ramon:inteligencia:seed[account_id]' if args[:account_id].blank?

      contagem = Ramon::InteligenciaSeed.new(Account.find(args[:account_id])).run
      contagem.each { |chave, valor| puts "#{chave}: #{valor}" }
    end
  end
end
