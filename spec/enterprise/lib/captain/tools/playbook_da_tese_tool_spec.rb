require 'rails_helper'

RSpec.describe Captain::Tools::PlaybookDaTeseTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:thesis) do
    create(:thesis, account: account, name: 'Auxílio-doença', description: 'Incapacidade temporária',
                    honorario_percentual: 30, honorario_n_mensalidades: 3)
  end

  describe '#perform' do
    before do
      create(:thesis_item, thesis: thesis, section: 'abertura', title: 'Saudação', content: 'Bom dia, tudo bem?')
      create(:thesis_item, thesis: thesis, section: 'objecao', title: nil, content: 'Advogado é caro? Só paga se ganhar.')
    end

    it 'acha a tese por parte do nome e monta o playbook por secao' do
      texto = tool.perform(tool_context, tese: 'auxílio')

      expect(texto).to include('Tese: Auxílio-doença', 'Descricao: Incapacidade temporária',
                               'Honorario: 30.0% dos atrasados + 3 mensalidades',
                               "## abertura (1)\n- Saudação: Bom dia, tudo bem?", "## objecao (1)\n- Advogado é caro?")
    end

    it 'filtra por secao quando pedida' do
      texto = tool.perform(tool_context, tese: 'auxílio', secao: 'objecao')

      expect(texto).to include('## objecao')
      expect(texto).not_to include('## abertura')
    end

    it 'chega na tese pelo lead_id' do
      lead = create(:lead, account: account, thesis: thesis)

      expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to include('Tese: Auxílio-doença')
    end

    it 'lista as teses ativas quando nao acha' do
      thesis
      create(:thesis, account: account, name: 'Inativa', active: false)

      texto = tool.perform(tool_context, tese: 'xyz')

      expect(texto).to include('Nao achei tese com "xyz"', 'Auxílio-doença')
      expect(texto).not_to include('Inativa')
    end

    it 'diz honorario nao configurado' do
      create(:thesis, account: account, name: 'BPC')

      expect(tool.perform(tool_context, tese: 'BPC')).to include('Honorario: nao configurado')
    end

    it 'recusa secao invalida' do
      expect(tool.perform(tool_context, tese: 'auxílio', secao: 'foo')).to start_with('Secao invalida')
    end

    it 'nao enxerga tese de outra conta' do
      create(:thesis, account: create(:account), name: 'Alheia')

      expect(tool.perform(tool_context, tese: 'Alheia')).to include('Nao achei tese')
    end
  end
end
