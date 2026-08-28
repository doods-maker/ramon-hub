# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RamonPortariaListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, portaria_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let!(:recepcao) { create(:team, account: account, name: 'Recepção') }
  let!(:controladoria) { create(:team, account: account, name: 'Controladoria') }
  let!(:advogados) { create(:team, account: account, name: 'Advogados') }

  def incoming(content, attrs = {})
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: content, content_attributes: attrs)
  end

  def fire(message)
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
  end

  def menus
    conversation.messages.outgoing.where(content_type: 'input_select')
  end

  it 'manda o menu com os 3 Setores na primeira mensagem' do
    expect { fire(incoming('oi')) }.to change { menus.count }.by(1)
    itens = menus.last.content_attributes['items']
    expect(itens.pluck('value')).to eq(%w[recepção controladoria advogados])
    expect(itens.pluck('title')).to eq(%w[Recepção Controladoria Advogados])
    expect(conversation.reload.team).to be_nil
  end

  it 'roteia pelo id do botão tocado' do
    fire(incoming('Advogados', { interactive_reply_id: 'advogados' }))
    expect(conversation.reload.team).to eq(advogados)
    expect(menus.count).to eq(0)
  end

  it 'roteia pelo texto quando o cliente digita o nome do Setor' do
    fire(incoming('controladoria'))
    expect(conversation.reload.team).to eq(controladoria)
  end

  it 'sorteia um agente do Setor entre os online' do
    agent = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: advogados, user: agent)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ agent.id.to_s => 'online' })

    fire(incoming('x', { interactive_reply_id: 'advogados' }))
    expect(conversation.reload.assignee).to eq(agent)
  end

  it 'reapresenta o menu uma vez e depois cai na Recepção' do
    fire(incoming('oi'))
    expect { fire(incoming('áudio sem texto')) }.to change { menus.count }.by(1)
    expect(menus.last.content).to eq(I18n.t('conversations.messages.portaria.menu_retry'))
    expect(conversation.reload.team).to be_nil

    expect { fire(incoming('outra coisa')) }.not_to(change { menus.count })
    expect(conversation.reload.team).to eq(recepcao)
  end

  it 'não faz nada se a conversa já tem Setor' do
    conversation.update!(team: controladoria)
    expect { fire(incoming('oi')) }.not_to(change { menus.count })
  end

  it 'ignora mensagens que não são do cliente' do
    outgoing = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'olá')
    expect { fire(outgoing) }.not_to(change { menus.count })
  end

  it 'não faz nada se a caixa não tem Portaria' do
    inbox.update!(portaria_enabled: false)
    expect { fire(incoming('oi')) }.not_to(change { menus.count })
  end

  it 'fica dormente se faltar algum dos 3 times' do
    advogados.destroy!
    expect { fire(incoming('oi')) }.not_to(change { menus.count })
  end
end
