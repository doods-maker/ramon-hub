# frozen_string_literal: true

namespace :ramon do
  namespace :documentos do
    desc 'Cria ou atualiza o assistente "Documentos" (instrucoes aprovadas, tools da etapa) e o liga a etapa Documentos. ' \
         'Nao liga a chave RAMON_ETAPA_DOCUMENTOS. Uso: rake ramon:documentos:assistente[account_id]'
    task :assistente, [:account_id] => :environment do |_task, args|
      raise ArgumentError, 'Uso: rake ramon:documentos:assistente[account_id]' if args[:account_id].blank?

      account = Account.find(args[:account_id])
      assistente = Ramon::Documentos::Assistente.criar_ou_atualizar!(account)
      etapa = account.lead_stages.find_by(label: Ramon::EtapaDeGanho::DOCUMENTOS)
      puts "assistente: #{assistente.id} (#{assistente.name})"
      puts etapa ? "etapa Documentos: #{etapa.id} ligada ao assistente" : 'etapa Documentos nao existe nesta conta: nada ligado'
    end
  end
end
