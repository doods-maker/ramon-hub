require 'rake'
require 'rails_helper'

# FORK-PONTO (ramon): seed idempotente da area Inteligencia. Depende do codigo
# enterprise (o CI FOSS remove a pasta), por isso o guard.
RSpec.describe Rake::Task, if: ChatwootApp.enterprise? do
  describe 'ramon:inteligencia:seed' do
    subject(:task) { described_class['ramon:inteligencia:seed'] }

    let(:account) { create(:account) }
    let(:atendimento) { account.captain_assistants.find_by!(name: 'Atendimento') }
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

    it 'renomeia o assistente pelo nome antigo e tira a marca morta (I-AS4, I-AS5)', :aggregate_failures do
      antigo = create(:captain_assistant, account: account, name: 'Atendimento (rascunho)',
                                          config: { 'ramon_modo_rascunho' => true })
      copiloto = create(:captain_assistant, account: account, name: 'Copiloto do Escritorio')

      rodar
      rodar

      expect(antigo.reload.name).to eq('Atendimento')
      expect(antigo.config).not_to have_key('ramon_modo_rascunho')
      expect(copiloto.reload.name).to eq('Copiloto do Escritório')
      expect(account.captain_assistants.count).to eq(2)
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

    context 'with as teses da conta' do
      let(:trabalhistas) { %w[acidente vínculo].map { |n| create(:thesis, account: account, name: "Trabalhista — #{n}").id } }
      let!(:bpc) { create(:thesis, account: account, name: 'BPC/LOAS (idoso ou pessoa com deficiência)') }

      before { trabalhistas }

      def faq_do(arquivo)
        pergunta = Rails.root.join("db/seeds/ramon/inteligencia/faq/#{arquivo}.md").read[/^## (.+)$/, 1].strip
        atendimento.responses.find_by!(question: pergunta)
      end

      it 'grava as teses pelo arquivo (trabalhista = todas as Trabalhista) e so preenche FAQ sem tese', :aggregate_failures do
        rodar
        expect(faq_do('bpc-loas').thesis_ids).to eq([bpc.id])
        expect(faq_do('trabalhista').thesis_ids).to match_array(trabalhistas)
        expect(faq_do('geral')).to have_attributes(geral: true, thesis_ids: [])

        editada = faq_do('bpc-loas')
        editada.update!(answer: 'Editada pelo Eduardo', thesis_ids: [])
        trocada = faq_do('geral')
        trocada.update!(geral: false, thesis_ids: [bpc.id])
        rodar

        expect(editada.reload).to have_attributes(answer: 'Editada pelo Eduardo', thesis_ids: [bpc.id])
        expect(trocada.reload).to have_attributes(geral: false, thesis_ids: [bpc.id])
      end

      it 'rake de teses so preenche a tese que falta e nao mexe em mais nada' do
        rodar
        faq = faq_do('bpc-loas')
        faq.update_columns(thesis_ids: [], answer: 'Resposta mexida') # rubocop:disable Rails/SkipsModelValidations
        teses = described_class['ramon:inteligencia:teses']
        teses.reenable

        expect { teses.invoke(account.id.to_s) }.to output(/faq_com_tese_preenchida: 1/).to_stdout
        expect(faq.reload).to have_attributes(thesis_ids: [bpc.id], answer: 'Resposta mexida')
      end
    end

    it 'respeita skill editada, renomeada, desligada ou criada na tela' do
      rodar
      editada, renomeada, desligada = atendimento.scenarios.order(:id).first(3)
      editada.update!(instruction: 'Como o Eduardo quer', edited: true)
      renomeada.update!(title: 'Nome novo na tela', edited: true)
      desligada.update!(enabled: false, edited: true)
      criada = create(:captain_scenario, assistant: atendimento, account: account, title: 'Criada na tela', edited: true)

      expect { rodar }.not_to change(Captain::Scenario, :count)
      expect(editada.reload.instruction).to eq('Como o Eduardo quer')
      expect(renomeada.reload.title).to eq('Nome novo na tela')
      expect(desligada.reload).not_to be_enabled
      expect(criada.reload).to be_enabled
    end

    it 'grava fala de exemplo e papeis do yml; skill editada so ganha o que esta vazio (A5)', :aggregate_failures do
      rodar
      copiloto = account.captain_assistants.find_by!(name: 'Copiloto do Escritório')
      skill = copiloto.scenarios.find_by!(seed_titulo: 'Funil hoje')
      expect(skill).to have_attributes(exemplo: 'Como está o funil hoje?', papeis: ['comercial'])

      skill.update!(edited: true, exemplo: 'Minha fala')
      skill.update_columns(papeis: []) # rubocop:disable Rails/SkipsModelValidations
      rodar

      expect(skill.reload).to have_attributes(exemplo: 'Minha fala', papeis: ['comercial'])
      expect(account.captain_assistants.find_by!(name: 'Atendimento').scenarios.where(exemplo: nil).count).to eq(0)
    end
  end
end
