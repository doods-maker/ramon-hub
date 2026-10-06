# frozen_string_literal: true

namespace :ramon do
  namespace :ia do
    desc 'Importa o caderno de provas como Casos de teste da IA (idempotente). ' \
         'Uso: rake ramon:ia:importar_caderno[account_id,assistente] — assistente = id ou nome (opcional)'
    task :importar_caderno, [:account_id, :assistente] => :environment do |_task, args|
      raise ArgumentError, 'Uso: rake ramon:ia:importar_caderno[account_id,assistente]' if args[:account_id].blank?

      contagem = Ramon::IaCadernoImport.new(Account.find(args[:account_id]), args[:assistente]).run
      contagem.each { |chave, valor| puts "#{chave}: #{valor}" }
    end
  end
end
