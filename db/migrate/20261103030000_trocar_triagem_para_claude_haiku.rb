# Internas saem da DeepSeek (App Review da Meta, 03/11): default novo e agentes já semeados.
class TrocarTriagemParaClaudeHaiku < ActiveRecord::Migration[7.1]
  def up
    change_column_default :triage_agents, :provider, 'anthropic'
    change_column_default :triage_agents, :model, 'claude-haiku-5-5'
    execute "UPDATE triage_agents SET provider = 'anthropic', model = 'claude-haiku-5-5' WHERE provider = 'deepseek'"
  end

  def down
    change_column_default :triage_agents, :provider, 'deepseek'
    change_column_default :triage_agents, :model, 'deepseek-chat'
  end
end
