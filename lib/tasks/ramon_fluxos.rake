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

      desc 'SO LEITURA: codigo x fluxos em sombra (max 8 dias). Uso: rake ramon:fluxos:reunioes:comparar[account_id,dias] (padrao 1 dia)'
      task :comparar, [:account_id, :dias] => :environment do |_task, args|
        account = conta.call(args)
        dias = (args[:dias].presence || 1).to_i
        puts 'AVISO: fluxos no comando (atividades iguais às do código): a comparação não vale' if Ramon::Fluxos::Reunioes.assumiu?(account)
        comparacoes = [Ramon::Fluxos::CompararAgendamentos, Ramon::Fluxos::CompararLembretes].map { |k| k.new(account, dias: dias) }
        puts comparacoes.map(&:relatorio).join("\n\n")
        total = comparacoes.sum { |c| c.linhas.size }
        geral = comparacoes.sum(&:divergencias).zero? ? "BATEU (#{total} comparações)" : "NÃO BATEU (#{total} comparações)"
        puts "\nResultado geral: #{total.zero? ? 'nada para comparar' : geral}"
      end
    end
  end
end
