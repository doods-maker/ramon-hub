require 'rails_helper'

RSpec.describe Captain::Tools::LinhaDaVidaTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:contact) { create(:contact, account: account, name: 'Maria', data_nascimento: 60.years.ago.to_date, sexo: 'F') }

  describe '#perform' do
    it 'devolve os casos da pessoa e os marcos etarios' do
      create(:lead, account: account, contact: contact, name: 'Caso 1')
      create(:lead, account: account, contact: contact, name: 'Caso 2')

      resultado = JSON.parse(tool.perform(tool_context, contact_id: contact.id.to_s))

      expect(resultado['pessoa']['nome']).to eq('Maria')
      expect(resultado['casos'].map { |c| c['nome'] }).to contain_exactly('Caso 1', 'Caso 2')
      expect(resultado['marcos'].map { |m| m['key'] }).to include('aposentadoria_idade_urbana')
    end

    it 'chega na pessoa pelo caso quando recebe lead_id' do
      lead = create(:lead, account: account, contact: contact)

      expect(JSON.parse(tool.perform(tool_context, lead_id: lead.id.to_s))['pessoa']['contact_id']).to eq(contact.id)
    end

    it 'devolve marcos vazios quando nao ha data de nascimento' do
      sem_data = create(:contact, account: account, name: 'Sem data')

      expect(JSON.parse(tool.perform(tool_context, contact_id: sem_data.id.to_s))['marcos']).to be_empty
    end

    it 'pede a pessoa quando nao consegue resolver' do
      expect(tool.perform(tool_context)).to include('Nao encontrei a pessoa')
    end
  end
end
