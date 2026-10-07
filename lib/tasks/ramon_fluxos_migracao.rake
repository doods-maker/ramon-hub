# frozen_string_literal: true

# B4.2+: qualquer migração código → fluxo (Ramon::Fluxos::Migracao::GRUPOS — reunioes, sla, …).
# Operação de cada uma: o plano da fatia, seção "Operação depois do deploy".
namespace :ramon do
  namespace :fluxos do
    namespace :migracao do
      conta = ->(args) { Account.find(args[:account_id].presence || raise(ArgumentError, 'informe o account_id')) }

      desc 'Cria (uma vez) os fluxos de uma migracao, em SOMBRA. Uso: rake ramon:fluxos:migracao:criar[grupo,account_id]'
      task :criar, [:grupo, :account_id] => :environment do |_task, args|
        account = conta.call(args)
        Ramon::Fluxos::Migracao.semear(account, args[:grupo])
        puts Ramon::Fluxos::Migracao.descrever(account, args[:grupo])
      end

      desc 'normal = os fluxos assumem (exige a env do grupo =on); sombra = devolve ao codigo. ' \
           'Uso: rake ramon:fluxos:migracao:modo[grupo,account_id,normal]'
      task :modo, [:grupo, :account_id, :modo] => :environment do |_task, args|
        account = conta.call(args)
        Ramon::Fluxos::Migracao.mudar_modo!(account, args[:grupo], args[:modo])
        puts Ramon::Fluxos::Migracao.descrever(account, args[:grupo])
      end
    end
  end
end
