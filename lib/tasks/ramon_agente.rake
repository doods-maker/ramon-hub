namespace :ramon do
  namespace :agente do
    desc 'Cria (idempotente) o AgentBot "Claude" que assina as notas do agente do hub'
    task :bot, [:account_id] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      bot = account.agent_bots.find_or_create_by!(name: 'Claude') { |b| b.description = 'Agente do hub (Claude Code na VPS)' }
      puts "AgentBot #{bot.id} pronto na conta #{account.id}"
    end
  end
end
