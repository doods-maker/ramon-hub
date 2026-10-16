# frozen_string_literal: true

# Funil automático: chave por peça (off | ensaio | on). Uso: rake ramon:funil:modo[account_id,peca,modo]
namespace :ramon do
  namespace :funil do
    desc 'Muda o modo de uma peca do funil automatico. Uso: rake ramon:funil:modo[account_id,peca,modo]'
    task :modo, [:account_id, :peca, :modo] => :environment do |_task, args|
      account = Account.find(args[:account_id].presence || raise(ArgumentError, 'informe o account_id'))
      Ramon::FunilAutomatico.mudar!(account, args[:peca], args[:modo])
      puts "conta #{account.id}: #{account.settings[Ramon::FunilAutomatico::CHAVE].inspect}"
    end
  end
end
