require 'rails_helper'

RSpec.describe TriageAgent do
  let(:account) { create(:account) }

  it 'valida presença de name, system_prompt, provider e model' do
    agent = account.triage_agents.new
    expect(agent).not_to be_valid
    expect(agent.errors.attribute_names).to include(:name, :system_prompt)
  end

  it 'rejeita provider fora da lista' do
    agent = account.triage_agents.new(name: 'X', system_prompt: 'p', provider: 'gemini', model: 'm')
    expect(agent).not_to be_valid
    expect(agent.errors.attribute_names).to include(:provider)
  end

  it 'aceita um agente deepseek válido com defaults' do
    agent = account.triage_agents.create!(name: 'X', system_prompt: 'p')
    expect(agent.provider).to eq('deepseek')
    expect(agent.model).to eq('deepseek-chat')
    expect(agent.sensitive).to be(false)
    expect(agent.active).to be(true)
  end

  it 'não permite dois agentes com o mesmo nome na mesma conta' do
    account.triage_agents.create!(name: 'X', system_prompt: 'p')
    expect { account.triage_agents.create!(name: 'X', system_prompt: 'q') }
      .to raise_error(ActiveRecord::RecordInvalid)
  end
end
