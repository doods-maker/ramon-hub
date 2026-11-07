require 'rails_helper'

# Casca da tool: repassa conversa, tema, as imagens do assistente e o estado do turno para Ramon::Documentos::PassoAPasso
# (a regra é testada lá).
RSpec.describe Captain::Tools::EnviarPassoAPassoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:conversa) { create(:conversation, account: account, status: :pending) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversa.id } }) }

  it 'prepara a imagem do tema guardada no assistente no estado do turno', :aggregate_failures do
    assistant.passos_a_passo.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'govbr_duas_etapas.png',
                                    content_type: 'image/png')
    allow(Ramon::Documentos::PassoAPasso).to receive(:preparar).and_return('ok')

    expect(tool.perform(tool_context, tema: 'govbr_duas_etapas')).to eq('ok')
    expect(Ramon::Documentos::PassoAPasso).to have_received(:preparar)
      .with(conversa, 'govbr_duas_etapas', imagens: [assistant.passos_a_passo.blobs.first], estado: tool_context.state)
  end

  it 'sem conversa: não envia nada' do
    expect(tool.perform(Struct.new(:state).new({}), tema: 'govbr_duas_etapas')).to eq(described_class::SEM_LEAD)
  end
end
