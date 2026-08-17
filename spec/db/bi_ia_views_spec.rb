require 'rails_helper'

# Views versionadas com scenic (Onda 3, Task 9). Sem model dedicado —
# consultamos direto via SQL, do jeito que o Metabase/BI vai consumir.
# A mensagem do Assistente (Captain::Assistant, enterprise/) e inserida por
# insert_all, sem instanciar o sender — assim a spec roda no CI FOSS.
# insert_all grava content_attributes como OBJETO json (o store grava STRING) — a view v2 le os dois.
RSpec.describe 'views bi_ia' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account) }

  def sql(query) = ActiveRecord::Base.connection.select_all(query).to_a

  def do_assistente(content, privada: false, content_attributes: {}, created_at: Time.current)
    # rubocop:disable Rails/SkipsModelValidations
    id = Message.insert_all([{ account_id: account.id, inbox_id: inbox.id, conversation_id: conversation.id,
                               message_type: 1, private: privada, sender_type: 'Captain::Assistant', sender_id: 1,
                               content: content, content_attributes: content_attributes,
                               created_at: created_at, updated_at: created_at }], returning: :id).first['id']
    # rubocop:enable Rails/SkipsModelValidations
    Message.find(id)
  end

  it 'bi_ia_rascunhos classifica a nota pelo carimbo' do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi')
    nota = do_assistente("RASCUNHO (revisar antes de enviar):\nOla, tudo bem?", privada: true)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent,
                     content: 'Ola, tudo bem?')

    linha = sql("SELECT * FROM bi_ia_rascunhos WHERE nota_id = #{nota.id}").first
    expect(linha).to include('desfecho' => 'igual', 'conversation_id' => conversation.id)
    expect(linha['minutos_ate_envio']).to be_present
  end

  it 'bi_ia_conversas mede a primeira resposta e marca com_ia' do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi',
                     created_at: 10.minutes.ago)
    do_assistente('Ola!', content_attributes: { 'ramon_piloto' => { 'modo' => 'piloto_limitado' } })

    linha = sql("SELECT * FROM bi_ia_conversas WHERE conversation_id = #{conversation.id}").first
    expect(linha['com_ia']).to be(true)
    expect(linha['pilotos_enviados']).to eq(1)
    expect(linha['minutos_primeira_resposta'].to_f).to be_between(9, 11)
  end

  it 'bi_ia_conversas nao mede primeira resposta quando o agente falou antes do cliente' do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent,
                     content: 'Ola, aqui e do escritorio', created_at: 10.minutes.ago)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi')

    linha = sql("SELECT * FROM bi_ia_conversas WHERE conversation_id = #{conversation.id}").first
    expect(linha['minutos_primeira_resposta']).to be_nil
    expect(linha['com_ia']).to be(false)
  end
end
