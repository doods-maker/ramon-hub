# frozen_string_literal: true

# B4.1 — agendamento de reuniões pelos fluxos, em sombra (spec §8 e §15).
# Operação: docs/superpowers/plans/2026-10-06-automacoes-fluxo-b4-lembretes.md (seção "Operação depois do deploy").
namespace :ramon do
  namespace :fluxos do
    namespace :reunioes do
      conta = ->(args) { Account.find(args[:account_id].presence || raise(ArgumentError, 'informe o account_id')) }

      desc 'Cria (uma vez) os 3 fluxos de reuniao em SOMBRA. Uso: rake ramon:fluxos:reunioes:sombra[account_id]'
      task :sombra, [:account_id] => :environment do |_task, args|
        account = conta.call(args)
        Ramon::Fluxos::Reunioes.semear(account)
        puts Ramon::Fluxos::Reunioes.descrever(account)
      end

      desc 'normal = os fluxos assumem o agendamento (exige RAMON_FLUXO_REUNIOES=on); sombra = devolve ao codigo. ' \
           'Uso: rake ramon:fluxos:reunioes:modo[account_id,normal]'
      task :modo, [:account_id, :modo] => :environment do |_task, args|
        account = conta.call(args)
        Ramon::Fluxos::Reunioes.mudar_modo!(account, args[:modo])
        puts Ramon::Fluxos::Reunioes.descrever(account)
      end
    end
  end
end
