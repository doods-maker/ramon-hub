# frozen_string_literal: true

namespace :ramon do
  namespace :roteiros do
    desc 'Seed idempotente dos roteiros da tese (db/seeds/ramon/roteiros) numa conta; passo editado na tela fica. ' \
         'Uso: rake ramon:roteiros:seed[account_id]'
    task :seed, [:account_id] => :environment do |_task, args|
      raise ArgumentError, 'Uso: rake ramon:roteiros:seed[account_id]' if args[:account_id].blank?

      Ramon::Roteiro::Seed.new(Account.find(args[:account_id])).run.each { |chave, valor| puts "#{chave}: #{valor}" }
    end
  end
end
