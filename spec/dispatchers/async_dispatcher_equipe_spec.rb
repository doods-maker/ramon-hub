require 'rails_helper'

# Hub surdo na caixa Equipe (ADR 0011): só o aviso nativo a quem participa ouve o evento.
describe AsyncDispatcher do
  subject(:dispatcher) { described_class.new.tap(&:load_listeners) }

  let(:account) { create(:account) }
  let!(:ana) { create(:user, account: account) }
  let(:inbox) { Ramon::Equipe.sincronizar(account, criar: true) }
  let(:geral) { inbox.conversations.first }
  let(:hub) do
    [RamonLeadListener, RamonFluxoListener, RamonAgenteListener, AutomationRuleListener, WebhookListener,
     ReportingEventListener, CsatSurveyListener, HookListener].map(&:instance)
  end

  def publicar(evento, data) = dispatcher.publish_event(evento, Time.zone.now, data)

  def nao_ouve(evento, *listeners)
    ouvintes = listeners.select { |listener| listener.respond_to?(evento) }
    ouvintes.each { |listener| expect(listener).not_to receive(evento) }
    ouvintes
  end

  it 'mensagem da Equipe vai só ao NotificationListener' do
    message = create(:message, conversation: geral, account: account, inbox: inbox, sender: ana, message_type: :outgoing)
    nao_ouve(:message_created, *hub)
    expect(NotificationListener.instance).to receive(:message_created)

    publicar('message.created', message: message)
  end

  it 'conversa, contato e caixa da Equipe não chegam ao hub' do
    ouvintes = %i[conversation_created contact_created inbox_created].flat_map { |evento| nao_ouve(evento, *hub) }
    expect(ouvintes).to include(RamonLeadListener.instance, WebhookListener.instance)

    publicar('conversation.created', conversation: geral)
    publicar('contact.created', contact: geral.contact)
    publicar('inbox.created', inbox: inbox)
  end

  it 'conversa de cliente continua chegando ao hub' do
    conversation = create(:conversation, account: account)
    expect(RamonLeadListener.instance).to receive(:conversation_created)

    publicar('conversation.created', conversation: conversation)
  end
end
