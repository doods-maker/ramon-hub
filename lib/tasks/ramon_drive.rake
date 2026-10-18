# frozen_string_literal: true

namespace :ramon do
  namespace :drive do
    desc 'Link (15 min) pra conectar a conta Google do escritorio ao Drive do hub. Abrir logado nessa conta.'
    task conectar: :environment do
      puts Ramon::DriveClient.url_conexao
    end
  end
end
