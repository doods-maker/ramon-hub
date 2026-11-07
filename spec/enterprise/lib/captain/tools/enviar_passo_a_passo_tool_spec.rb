require 'rails_helper'

# Casca da tool: repassa conversa, tema e as imagens do assistente para Ramon::Documentos::PassoAPasso (a regra é testada lá).
RSpec.describe Captain::Tools::EnviarPassoAPassoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:conversa) { create(:conversation, account: account, status: :pending) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversa.id } }) }

  it 'manda a imagem do tema guardada no assistente', :aggregate_failures do
    assistant.passos_a_passo.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'govbr_duas_etapas.png',
                                    content_type: 'image/png')
    allow(Ramon::Documentos::PassoAPasso).to receive(:enviar).and_return('ok')

    expect(tool.perform(tool_context, tema: 'govbr_duas_etapas')).to eq('ok')
    expect(Ramon::Documentos::PassoAPasso).to have_received(:enviar)
      .with(conversa, 'govbr_duas_etapas', imagens: [assistant.passos_a_passo.blobs.first], remetente: assistant)
  end

  it 'sem conversa: não envia nada' do
    expect(tool.perform(Struct.new(:state).new({}), tema: 'govbr_duas_etapas')).to eq(described_class::SEM_LEAD)
  end
end
