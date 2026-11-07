require 'rails_helper'

RSpec.describe Ramon::RespostaIaAtrasadaJob do
  let(:conversation) { create(:conversation, status: :pending) }
  let(:params) { { message_type: :outgoing, account_id: conversation.account_id, inbox_id: conversation.inbox_id, content: 'resposta da IA' } }
  let!(:cliente) { create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox) }

  def nova(tipo) = create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox, message_type: tipo)

  it 'envia a resposta quando nada mudou durante a espera' do
    expect { described_class.perform_now(conversation, params, cliente.id) }.to change { conversation.messages.count }.by(1)
  end

  it 'não envia se o cliente escreveu de novo (a resposta da mensagem nova cobre tudo)' do
    nova(:incoming)
    expect { described_class.perform_now(conversation, params, cliente.id) }.not_to(change { conversation.messages.count })
  end

  it 'não envia se uma pessoa respondeu durante a espera' do
    nova(:outgoing)
    expect { described_class.perform_now(conversation, params, cliente.id) }.not_to(change { conversation.messages.count })
  end

  it 'não envia se a conversa saiu da IA (pausada/assumida)' do
    conversation.update!(status: :open)
    expect { described_class.perform_now(conversation, params, cliente.id) }.not_to(change { conversation.messages.count })
  end

  it 'com a imagem do passo a passo do turno: uma mensagem só, o texto como legenda da imagem', :aggregate_failures do
    imagem = ActiveStorage::Blob.create_and_upload!(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'meu_inss_cnis.png',
                                                    content_type: 'image/png')
    expect { described_class.perform_now(conversation, params, cliente.id, passo_a_passo: imagem.id) }
      .to change { conversation.messages.count }.by(1)
    enviada = conversation.messages.reorder(:id).last
    expect([enviada.content, enviada.attachments.size]).to eq(['resposta da IA', 1])
  end

  it 'aviso de handoff sai mesmo com a conversa já aberta' do
    conversation.update!(status: :open)
    expect { described_class.perform_now(conversation, params, cliente.id, handoff: true) }.to change { conversation.messages.count }.by(1)
  end
end
