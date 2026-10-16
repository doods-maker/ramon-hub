require 'rails_helper'

# As tools do roteiro deixam no state a chave do passo que mostraram à IA (Ramon::Roteiro::Opcoes só põe botões
# na pergunta desse passo).
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Passo do roteiro mostrado à IA' do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:thesis) { create(:thesis, account: account) }
  let(:lead) { create(:lead, account: account, thesis: thesis) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:mostrado) { Captain::Tools::RoteiroPassoAtualTool::MOSTRADO }

  before do
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'situacao', position: 0, tipo_resposta: 'sim_nao')
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'funcao', position: 1, tipo_resposta: 'texto')
  end

  it 'Passo atual grava o passo que mostrou' do
    Captain::Tools::RoteiroPassoAtualTool.new(assistant).perform(tool_context, lead_id: lead.id.to_s)
    expect(tool_context.state[mostrado]).to eq('situacao')
  end

  it 'Registrar grava o próximo passo' do
    Captain::Tools::RoteiroRegistrarTool.new(assistant).perform(tool_context, lead_id: lead.id.to_s, chave: 'situacao', valor: 'sim')
    expect(tool_context.state[mostrado]).to eq('funcao')
  end
end
# rubocop:enable RSpec/DescribeClass
