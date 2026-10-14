require 'rails_helper'

# rubocop:disable RSpec/DescribedClass -- constante explícita (regra da F5: reload no CI)
# Revisão final F5, I1 e I3: só o lead da conversa recebe dado pessoal, e nada fica em claro no ToolRun.
RSpec.describe Captain::Tools::RegistrarDadosContratoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { Captain::Tools::RegistrarDadosContratoTool.new(assistant) }
  let(:conversation) { create(:conversation, account: account) }
  let(:contact) { create(:contact, account: account, name: 'João') }

  before { create(:lead, account: account, contact: contact, conversation: conversation) }

  it 'grava no lead da conversa, nunca no lead_id que vier' do
    outro = create(:lead, account: account, contact: create(:contact, account: account, name: 'Maria'))
    contexto = Struct.new(:state).new({ conversation: { id: conversation.id } })

    tool.perform(contexto, lead_id: outro.id.to_s, nome: 'João da Silva')

    expect(contact.reload.name).to eq('João da Silva')
    expect(outro.contact.reload.name).to eq('Maria')
  end

  it 'no teste nenhum campo fica em claro, nem na simulação nem nos params' do
    teste = Struct.new(:state).new({ source: 'teste' })

    saida = tool.execute(teste, nome: 'João da Silva', cpf: '52998224725', rua: 'Rua A')

    expect(saida).to eq('[TESTE] faria registrar_dados_contrato(nome: ***, cpf: ***, rua: ***)')
    expect(Captain::ToolRun.last.params).to eq('nome' => '***', 'cpf' => '***', 'rua' => '***')
    expect(contact.reload.name).to eq('João')
  end
end
# rubocop:enable RSpec/DescribedClass
