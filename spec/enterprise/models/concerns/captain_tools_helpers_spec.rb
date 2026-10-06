require 'rails_helper'

RSpec.describe Concerns::CaptainToolsHelpers, type: :concern do
  # Create a test class that includes the concern
  let(:test_class) do
    Class.new do
      include Concerns::CaptainToolsHelpers

      def self.name
        'TestClass'
      end
    end
  end

  let(:test_instance) { test_class.new }

  describe 'TOOL_REFERENCE_REGEX' do
    it 'matches tool references in text' do
      text = 'Use [@Add Contact Note](tool://add_contact_note) and [Update Priority](tool://update_priority)'
      matches = text.scan(Concerns::CaptainToolsHelpers::TOOL_REFERENCE_REGEX)

      expect(matches.flatten).to eq(%w[add_contact_note update_priority])
    end

    it 'does not match invalid formats' do
      invalid_formats = [
        '<tool://invalid>',
        'tool://invalid',
        '(tool:invalid)',
        '(tool://)',
        '(tool://with/slash)',
        '(tool://add_contact_note)',
        '[@Tool](tool://)',
        '[Tool](tool://with/slash)',
        '[](tool://valid)'
      ]

      invalid_formats.each do |format|
        matches = format.scan(Concerns::CaptainToolsHelpers::TOOL_REFERENCE_REGEX)
        expect(matches).to be_empty, "Should not match: #{format}"
      end
    end
  end

  describe '.resolve_tool_class' do
    it 'resolves valid tool classes' do
      # Mock the constantize to return a class
      stub_const('Captain::Tools::AddContactNoteTool', Class.new)

      result = test_class.resolve_tool_class('add_contact_note')
      expect(result).to eq(Captain::Tools::AddContactNoteTool)
    end

    it 'returns nil for invalid tool classes' do
      result = test_class.resolve_tool_class('invalid_tool')
      expect(result).to be_nil
    end

    it 'converts snake_case to PascalCase' do
      stub_const('Captain::Tools::AddPrivateNoteTool', Class.new)

      result = test_class.resolve_tool_class('add_private_note')
      expect(result).to eq(Captain::Tools::AddPrivateNoteTool)
    end
  end

  describe '#extract_tool_ids_from_text' do
    it 'extracts tool IDs from text' do
      text = 'First [@Add Contact Note](tool://add_contact_note) then [@Update Priority](tool://update_priority)'
      result = test_instance.extract_tool_ids_from_text(text)

      expect(result).to eq(%w[add_contact_note update_priority])
    end

    it 'returns unique tool IDs' do
      text = 'Use [@Add Contact Note](tool://add_contact_note) and [@Contact Note](tool://add_contact_note) again'
      result = test_instance.extract_tool_ids_from_text(text)

      expect(result).to eq(['add_contact_note'])
    end

    it 'returns empty array for blank text' do
      expect(test_instance.extract_tool_ids_from_text('')).to eq([])
      expect(test_instance.extract_tool_ids_from_text(nil)).to eq([])
      expect(test_instance.extract_tool_ids_from_text('   ')).to eq([])
    end

    it 'returns empty array when no tools found' do
      text = 'This text has no tool references'
      result = test_instance.extract_tool_ids_from_text(text)

      expect(result).to eq([])
    end

    it 'handles complex text with multiple tools' do
      text = <<~TEXT
        Start with [@Add Contact Note](tool://add_contact_note) to document.
        Then use [@Update Priority](tool://update_priority) if needed.
        Finally [@Add Private Note](tool://add_private_note) for internal notes.
      TEXT

      result = test_instance.extract_tool_ids_from_text(text)
      expect(result).to eq(%w[add_contact_note update_priority add_private_note])
    end
  end

  describe 'nivel das ferramentas (config/agents/tools.yml)' do
    let(:ferramentas) { Captain::Assistant.built_in_agent_tools }

    def ids_do_nivel(nivel)
      ferramentas.select { |tool| tool[:nivel] == nivel }.pluck(:id)
    end

    it 'toda ferramenta tem um dos quatro niveis' do
      expect(ferramentas.pluck(:nivel).uniq).to match_array(%w[consulta interna sugestao rascunho])
    end

    it 'sugestao = exatamente as ferramentas que herdam das bases de escrita com aprovacao' do
      herdeiras = ferramentas.pluck(:id).select do |id|
        klass = Captain::Assistant.resolve_tool_class(id)
        klass < Captain::Tools::RamonEscritaTool || klass < Captain::Tools::AdvboxMcpEscritaTool
      end

      expect(ids_do_nivel('sugestao')).to match_array(herdeiras)
    end

    it 'rascunho pro cliente = pedir documentos e link do portal' do
      expect(ids_do_nivel('rascunho')).to match_array(%w[solicitar_documento enviar_link_portal])
    end
  end

  describe 'sistema das ferramentas (config/agents/tools.yml)' do
    let(:ferramentas) { Captain::Assistant.built_in_agent_tools }

    it 'toda ferramenta diz em qual sistema mexe' do
      expect(ferramentas.pluck(:sistema).uniq).to match_array(%w[funil advbox motor zapsign calcom faq conversa])
    end

    it 'toda ferramenta *_advbox mexe no AdvBox' do
      advbox = ferramentas.select { |tool| tool[:id].end_with?('_advbox') }
      expect(advbox.pluck(:sistema).uniq).to eq(['advbox'])
    end
  end
end
