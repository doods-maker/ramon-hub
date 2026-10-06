# frozen_string_literal: true

namespace :ramon do
  namespace :contatos do
    desc 'SO LEITURA: lista contatos duplicados pela grafia do celular (com/sem 55 e o 9o digito). ' \
         'Nao mescla nada. Uso: rake ramon:contatos:telefones_duplicados[account_id]'
    task :telefones_duplicados, [:account_id] => :environment do |_task, args|
      raise ArgumentError, 'Uso: rake ramon:contatos:telefones_duplicados[account_id]' if args[:account_id].blank?

      grupos = Ramon::TelefonesDuplicados.new(Account.find(args[:account_id])).grupos
      grupos.each do |grupo|
        puts grupo.map { |contato| "##{contato.id} #{contato.name} (#{contato.phone_number})" }.join('  |  ')
      end
      puts "#{grupos.size} grupo(s) de duplicados"
    end
  end
end
