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

    desc 'Preenche so a tese das FAQs do seed que ainda nao tem (nao mexe em mais nada). ' \
         'Uso: rake ramon:inteligencia:teses[account_id]'
    task :teses, [:account_id] => :environment do |_task, args|
      raise ArgumentError, 'Uso: rake ramon:inteligencia:teses[account_id]' if args[:account_id].blank?

      total = Ramon::InteligenciaSeed.new(Account.find(args[:account_id])).preencher_teses
      puts "faq_com_tese_preenchida: #{total}"
    end
  end
end
