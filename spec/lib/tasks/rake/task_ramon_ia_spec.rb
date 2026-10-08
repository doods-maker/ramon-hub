require 'rake'
require 'rails_helper'

# FORK-PONTO (ramon): importa o caderno de provas como Casos de teste da IA.
# Depende do codigo enterprise (o CI FOSS remove a pasta), por isso o guard.
RSpec.describe Rake::Task, if: ChatwootApp.enterprise? do
  describe 'ramon:ia:importar_caderno' do
    subject(:task) { described_class['ramon:ia:importar_caderno'] }

    let(:account) { create(:account) }
    let!(:atendimento) { create(:captain_assistant, account: account, name: 'Atendimento') }
    let!(:copiloto) { create(:captain_assistant, account: account, name: 'Copiloto do Escritório') }
    let(:yml) { YAML.safe_load(Rails.root.join('db/seeds/ramon/ia_casos.yml').read) }

    def rodar(*)
      task.reenable
      task.invoke(account.id.to_s, *)
    end

    def casos_do(assistant)
      Captain::IaCaso.where(assistant_id: assistant.id)
    end

    it 'importa os casos do caderno com criterios das marcas e rubrica literal', :aggregate_failures do
      rodar

      total = yml['assistentes'].sum { |bloco| bloco['casos'].size }
      expect(Captain::IaCaso.where(account_id: account.id, origem: 'caderno').count).to eq(total)
      expect(casos_do(copiloto).pluck(:codigo)).to all(start_with('C'))
      a11 = casos_do(atendimento).find_by!(codigo: 'A11')
      expect(a11.criterios).to include('handoff' => 'sim')
      expect(a11.criterios['rubrica']).to include('[HUM] handoff').and include('NUNCA podem acontecer')
      expect(a11.message_history).to eq([{ role: 'user', content: 'quero falar com o Dr. Ramon' }])
      expect(casos_do(atendimento).find_by!(codigo: 'A14')).not_to be_ativo
    end

    it 'e idempotente e nao sobrescreve caso editado na tela', :aggregate_failures do
      rodar
      a5 = casos_do(atendimento).find_by!(codigo: 'A5')
      a5.update!(titulo: 'Editado pelo Eduardo', ativo: false)

      expect { rodar }.not_to change(Captain::IaCaso, :count)
      expect(a5.reload).to have_attributes(titulo: 'Editado pelo Eduardo', ativo: false)
    end

    it 'com assistente importa so o bloco dele (por id ou nome)', :aggregate_failures do
      rodar(copiloto.id.to_s)
      expect(casos_do(atendimento).count).to eq(0)
      expect(casos_do(copiloto).count).to be > 5

      rodar('Atendimento')
      expect(casos_do(atendimento).count).to be > 30
    end
  end
end
