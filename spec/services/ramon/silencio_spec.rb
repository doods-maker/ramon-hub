require 'rails_helper'

RSpec.describe Ramon::Silencio do
  let(:dispatcher) { Rails.configuration.dispatcher }

  describe '.executar' do
    it 'cala o Dispatcher dentro do bloco e devolve o normal depois' do
      allow(dispatcher.sync_dispatcher).to receive(:dispatch)

      described_class.executar { dispatcher.dispatch('message.created', Time.zone.now, {}) }
      expect(dispatcher.sync_dispatcher).not_to have_received(:dispatch)

      dispatcher.dispatch('message.created', Time.zone.now, {})
      expect(dispatcher.sync_dispatcher).to have_received(:dispatch).once
    end

    it 'desliga a flag mesmo quando o bloco levanta exceção' do
      expect { described_class.executar { raise ArgumentError, 'falhou' } }.to raise_error(ArgumentError)

      expect(Current.importacao_silenciosa).to be_falsey
    end

    it 'devolve o valor do bloco' do
      expect(described_class.executar { 42 }).to eq(42)
    end
  end

  describe 'mensagem criada dentro do silêncio' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)
    end

    before { conversation }

    def criar_mensagem(message_type, silencio: true)
      criar = lambda do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: message_type,
                         sender: message_type == :incoming ? contact : nil, content: 'oi')
      end
      silencio ? described_class.executar(&criar) : criar.call
    end

    # A trava de verdade: lead, fluxo, IA e automação rodam nos listeners do AsyncDispatcher (EventDispatcherJob)
    # e o reenvio ao WhatsApp no SendReplyJob. Fora do silêncio a mesma mensagem enfileira os dois.
    it 'fora do silêncio enfileira EventDispatcherJob e SendReplyJob; dentro, nenhum dos dois' do
      expect { criar_mensagem(:outgoing, silencio: false) }.to have_enqueued_job(EventDispatcherJob).at_least(:once)
      expect { criar_mensagem(:outgoing, silencio: false) }.to have_enqueued_job(SendReplyJob).at_least(:once)

      expect { criar_mensagem(:outgoing) }.not_to have_enqueued_job(EventDispatcherJob)
      expect { criar_mensagem(:outgoing) }.not_to have_enqueued_job(SendReplyJob)
      expect { criar_mensagem(:incoming) }.not_to have_enqueued_job(EventDispatcherJob)
    end

    it 'não reabre a conversa, não chama templates e não passa evento ao Dispatcher (lead, fluxo, IA, automação)' do
      allow(MessageTemplates::HookExecutionService).to receive(:new)

      expect { criar_mensagem(:incoming) }.not_to have_enqueued_job(EventDispatcherJob)

      expect(MessageTemplates::HookExecutionService).not_to have_received(:new)
      expect(conversation.reload).to be_resolved
    end

    it 'não reenvia nada ao WhatsApp' do
      expect { criar_mensagem(:outgoing) }.not_to have_enqueued_job(SendReplyJob)
    end

    it 'não cria lead' do
      expect { criar_mensagem(:incoming) }.not_to change(Lead, :count)
    end
  end
end
