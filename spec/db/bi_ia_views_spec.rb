require 'rails_helper'

# Views versionadas com scenic (Onda 3, Task 9). Sem model dedicado —
# consultamos direto via SQL, do jeito que o Metabase/BI vai consumir.
RSpec.describe 'views bi_ia' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  def sql(query) = ActiveRecord::Base.connection.select_all(query).to_a

  it 'bi_ia_rascunhos classifica a nota pelo carimbo' do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi')
    nota = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, private: true,
                            sender: assistant, content: "RASCUNHO (revisar antes de enviar):\nOla, tudo bem?")
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent,
                     content: 'Ola, tudo bem?')

    linha = sql("SELECT * FROM bi_ia_rascunhos WHERE nota_id = #{nota.id}").first
    expect(linha).to include('desfecho' => 'igual', 'conversation_id' => conversation.id)
    expect(linha['minutos_ate_envio']).to be_present
  end

  it 'bi_ia_conversas mede a primeira resposta e marca com_ia' do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi',
                     created_at: 10.minutes.ago)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: assistant,
                     content: 'Ola!', content_attributes: { 'ramon_piloto' => { 'modo' => 'piloto_limitado' } })

    linha = sql("SELECT * FROM bi_ia_conversas WHERE conversation_id = #{conversation.id}").first
    expect(linha['com_ia']).to be(true)
    expect(linha['pilotos_enviados']).to eq(1)
    expect(linha['minutos_primeira_resposta'].to_f).to be_between(9, 11)
  end
end
