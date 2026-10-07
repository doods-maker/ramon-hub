require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Conversations::Faqs', type: :request, if: ChatwootApp.enterprise? do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistente) { create(:captain_assistant, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/faqs" }

  before do
    create(:inbox_member, user: agente, inbox: inbox)
    create(:captain_inbox, captain_assistant: assistente, inbox: inbox)
    create(:message, account: account, conversation: conversa, inbox: inbox, message_type: :incoming, content: 'A perícia é paga?')
  end

  def resposta(texto = 'Não, é gratuita.', privada: false)
    create(:message, account: account, conversation: conversa, inbox: inbox, message_type: :outgoing, content: texto, private: privada)
  end

  def virar(mensagem, usuario = agente)
    post url, params: { message_id: mensagem.id }, headers: usuario.create_new_auth_token, as: :json
  end

  it 'cria a FAQ PENDENTE ligada à conversa e o 2º clique devolve a mesma', :aggregate_failures do
    mensagem = resposta
    virar(mensagem)

    expect(response).to have_http_status(:created)
    faq = assistente.responses.last
    expect(faq).to have_attributes(question: 'A perícia é paga?', answer: 'Não, é gratuita.', status: 'pending', documentable: conversa)

    virar(mensagem)
    expect(response.parsed_body).to include('id' => faq.id, 'assistant_id' => assistente.id, 'ja_existia' => true)
    expect(assistente.responses.count).to eq(1)
  end

  it 'nota privada não vira FAQ (422 SEM_RESPOSTA)', :aggregate_failures do
    virar(resposta('nota', privada: true))

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq('erro' => 'SEM_RESPOSTA')
  end

  it 'caixa sem assistente usa o assistente que atende alguma caixa; sem nenhum, 422 SEM_ASSISTENTE', :aggregate_failures do
    outra = create(:inbox, account: account)
    create(:inbox_member, user: agente, inbox: outra)
    conversa_outra = create(:conversation, account: account, inbox: outra)
    create(:message, account: account, conversation: conversa_outra, inbox: outra, message_type: :incoming, content: 'Oi?')
    mensagem = create(:message, account: account, conversation: conversa_outra, inbox: outra, message_type: :outgoing, content: 'Olá!')
    post "/api/v1/accounts/#{account.id}/conversations/#{conversa_outra.display_id}/faqs",
         params: { message_id: mensagem.id }, headers: agente.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('assistant_id' => assistente.id)

    CaptainInbox.delete_all
    virar(resposta('Outra resposta.'))
    expect(response.parsed_body).to eq('erro' => 'SEM_ASSISTENTE')
  end

  it 'quem não vê a conversa não cria' do
    de_fora = create(:user, account: account, role: :agent)
    virar(resposta, de_fora)

    expect(response).to have_http_status(:unauthorized)
  end
end
