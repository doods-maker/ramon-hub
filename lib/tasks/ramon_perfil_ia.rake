# frozen_string_literal: true

namespace :ramon do
  namespace :perfil_ia do
    desc 'Migra os modos do copiloto (caixas e conversas) para o Perfil da IA e as Pausas, em todas as contas (idempotente)'
    task migrar: :environment do
      Account.find_each { |account| puts "conta #{account.id}: #{Ramon::PerfilIa::Migracao.rodar(account).inspect}" }
    end
  end
end
