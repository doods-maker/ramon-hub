require 'rake'
require 'rails_helper'

# FORK-PONTO (ramon): seed idempotente da area Inteligencia. Depende do codigo
# enterprise (o CI FOSS remove a pasta), por isso o guard.
RSpec.describe Rake::Task, if: ChatwootApp.enterprise? do
  describe 'ramon:inteligencia:seed' do
    subject(:task) { described_class['ramon:inteligencia:seed'] }

    let(:account) { create(:account) }
    let(:atendimento) { account.captain_assistants.find_by!(name: 'Atendimento (rascunho)') }
    let(:yml) { YAML.safe_load(Rails.root.join('db/seeds/ramon/inteligencia/assistentes.yml').read).fetch('assistentes') }
    let(:total_skills) { yml.sum { |a| a['skills'].size } }

    def rodar
      task.reenable
      task.invoke(account.id.to_s)
    end

    it 'cria assistentes, skills e FAQ a partir dos seeds' do
      rodar
      expect(account.captain_assistants.pluck(:name)).to match_array(yml.pluck('name'))
      expect(Captain::Scenario.where(account: account).count).to eq(total_skills)
      expect(atendimento.responses.approved.count).to be > 10
    end

    it 'e idempotente: rodar duas vezes nao duplica' do
      rodar
      expect { rodar }.not_to(change do
        [account.captain_assistants.count, Captain::Scenario.where(account: account).count, atendimento.responses.count]
      end)
    end

    it 'desabilita skill que nao esta no yml e preserva FAQ editada na UI' do
      rodar
      extra = create(:captain_scenario, assistant: atendimento, account: account, title: 'Skill antiga')
      faq = atendimento.responses.first
      faq.update!(answer: 'Resposta editada pelo Eduardo')
      expect(faq.reload).to be_edited

      rodar
      expect(extra.reload).not_to be_enabled
      expect(faq.reload.answer).to eq('Resposta editada pelo Eduardo')
    end
  end
end
