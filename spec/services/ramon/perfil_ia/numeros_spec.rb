require 'rails_helper'

# Números por Etapa (spec "Como a IA atende", sugestão 1). insert_all grava content_attributes como OBJETO json;
# o store do Message grava STRING — a consulta lê os dois (a linha criada pelo factory cobre o segundo).
RSpec.describe Ramon::PerfilIa::Numeros do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def carimbar(*attrs, created_at: Time.current)
    linhas = attrs.map do |ca|
      { account_id: account.id, inbox_id: inbox.id, conversation_id: conversation.id, message_type: 1, private: false,
        sender_type: 'User', sender_id: 1, content: 'x', content_attributes: ca, created_at: created_at, updated_at: created_at }
    end
    Message.insert_all(linhas) # rubocop:disable Rails/SkipsModelValidations
  end

  def revisado(desfecho, alvo: 'padrao', etapa: 'fase-novo')
    { 'ramon_rascunho_ia' => { 'nota_id' => 1, 'desfecho' => desfecho, 'similaridade' => 1.0, 'alvo' => alvo, 'etapa' => etapa } }
  end

  # Todos os exemplos rodam a consulta de verdade (GROUP BY sem o ORDER BY do default_scope do Message).
  it 'sem carimbo com alvo e Etapa = sem dados ainda (chave ausente)' do
    expect(described_class.todos(account)).to eq({}) # sem linha nenhuma
    carimbar({ 'ramon_piloto' => { 'modo' => 'piloto_limitado' } }, {})

    expect(described_class.de(account, 'padrao')).to eq({})
  end

  it 'consulta que quebra (content_attributes que não é JSON) = sem números, com aviso no log' do
    allow(described_class).to receive(:linhas).and_raise(ActiveRecord::StatementInvalid, 'PG::InvalidTextRepresentation')
    allow(Rails.logger).to receive(:warn)

    expect(described_class.todos(account)).to eq({})
    expect(described_class.de(account, 'padrao')).to eq({})
    expect(Rails.logger).to have_received(:warn).with(/Numeros.*StatementInvalid/).twice
  end

  it 'conta por alvo e Etapa nos 30 dias; 20 revisados com 19 iguais numa Etapa em rascunho sugerem Sozinha', :aggregate_failures do
    # padrão salvo nenhum = INICIAL (Marcador _inicio): fase-novo está em rascunho
    carimbar(*Array.new(19) { revisado('igual') }, revisado('editado'),
             { 'ramon_piloto' => { 'perfil' => 'Cautelosa', 'alvo' => 'padrao', 'etapa' => 'fase-novo', 'handoff' => true } },
             { 'ramon_ia_rascunho' => { 'alvo' => 'padrao', 'etapa' => 'fase-novo', 'motivo' => 'handoff', 'handoff' => true } },
             revisado('descartado', alvo: 'tese:9'))
    carimbar(revisado('igual'), created_at: 31.days.ago)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     content_attributes: { 'ramon_piloto' => { 'alvo' => 'padrao', 'etapa' => 'fase-qualificacao', 'handoff' => false } })

    numeros = described_class.de(account, 'padrao')
    expect(numeros['fase-novo']).to eq(enviadas: 1, rascunhos: { igual: 19, editado: 1, descartado: 0 }, chamou_equipe: 2,
                                       sugerir_sozinha: true)
    expect(numeros['fase-qualificacao']).to include(enviadas: 1, chamou_equipe: 0, sugerir_sozinha: false)
    # tese que segue o padrão (sem cfg próprio): conta, mas não sugere
    expect(described_class.todos(account)['tese:9']['fase-novo']).to include(rascunhos: { igual: 0, editado: 0, descartado: 1 },
                                                                             sugerir_sozinha: false)
  end

  it 'não sugere com menos de 20 revisados nem com a Etapa já Sozinha' do
    carimbar(*Array.new(19) { revisado('igual') })
    expect(described_class.de(account, 'padrao')['fase-novo'][:sugerir_sozinha]).to be(false)

    carimbar(revisado('igual'))
    account.update!(settings: { 'ia_atendimento' => { 'padrao' => { 'base' => 'cautelosa', 'marcador' => 'fase-novo' } } })
    expect(described_class.de(account, 'padrao')['fase-novo'][:sugerir_sozinha]).to be(false)
  end
end
