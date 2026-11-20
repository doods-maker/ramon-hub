require 'rails_helper'

RSpec.describe Whatsapp::Coexistencia::ImportarHistoricoService do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', phone_number: '+554830000000', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:telefone_cliente) { '5548999991111' }
  let(:mensagens) do
    [
      { from: telefone_cliente, id: 'wamid.cliente1', timestamp: '1700000000', type: 'text', text: { body: 'Oi, preciso de ajuda' } },
      { from: '554830000000', to: telefone_cliente, id: 'wamid.escritorio1', timestamp: '1700000100', type: 'text',
        text: { body: 'Claro, me conta' } }
    ]
  end
  let(:lote) do
    { metadata: { phase: 0, chunk_order: 1, progress: 55 },
      threads: [{ id: telefone_cliente, context: { wa_id: telefone_cliente, username: 'Maria' }, messages: mensagens }] }
  end
  let(:value) { { metadata: { display_phone_number: '554830000000', phone_number_id: '123456789' }, history: [lote] } }

  def importar(payload = value)
    described_class.new(channel: channel, value: payload).perform
  end

  it 'cria o contato, uma conversa resolvida marcada como importada e as mensagens na direção certa' do
    importar

    contato = inbox.contact_inboxes.find_by!(source_id: telefone_cliente).contact
    expect(contato).to have_attributes(name: 'Maria', phone_number: "+#{telefone_cliente}")

    conversa = inbox.conversations.find_by!(contact_id: contato.id)
    expect(conversa).to be_resolved
    expect(conversa.additional_attributes[Whatsapp::Coexistencia::MARCA]).to be(true)
    expect(conversa.last_activity_at).to eq(Time.zone.at(1_700_000_100))

    entrada, saida = conversa.messages.reorder(:created_at).to_a
    expect(entrada).to have_attributes(message_type: 'incoming', sender: contato, source_id: 'wamid.cliente1',
                                       content: 'Oi, preciso de ajuda', created_at: Time.zone.at(1_700_000_000))
    expect(saida).to have_attributes(message_type: 'outgoing', sender: nil, source_id: 'wamid.escritorio1', content: 'Claro, me conta')
    expect(entrada.content_attributes[Whatsapp::Coexistencia::MARCA]).to be(true)
  end

  it 'é idempotente pelo wamid e reaproveita a conversa importada' do
    importar
    expect { importar }.not_to change(Message, :count)
    expect(inbox.conversations.count).to eq(1)
  end

  it 'lote seguinte do mesmo contato cai na mesma conversa importada, sem duplicar mensagem' do
    importar
    mensagens << { from: telefone_cliente, id: 'wamid.cliente2', timestamp: '1700000200', type: 'text', text: { body: 'Mandei os laudos' } }

    expect { importar }.to change(Message, :count).by(1)

    conversa = inbox.conversations.sole
    expect(conversa.messages.pluck(:source_id)).to contain_exactly('wamid.cliente1', 'wamid.escritorio1', 'wamid.cliente2')
    expect(conversa.reload.last_activity_at).to eq(Time.zone.at(1_700_000_200))
  end

  it 'thread só com wamid que já chegou não cria contato na caixa nem conversa importada' do
    create(:message, account: inbox.account, inbox: inbox, source_id: 'wamid.cliente1')
    mensagens.replace([mensagens.first])

    expect { importar }.not_to change(ContactInbox, :count)
    expect(inbox.conversations.where("additional_attributes ->> ? = 'true'", Whatsapp::Coexistencia::MARCA)).to be_empty
  end

  it 'telefone que o contato não aceita pula só aquela thread e o lote segue' do
    ruim = { id: '0123456789', context: { wa_id: '0123456789' },
             messages: [{ from: '0123456789', id: 'wamid.ruim', timestamp: '1700000000', type: 'text', text: { body: 'oi' } }] }
    lote[:threads].unshift(ruim)

    importar

    expect(Message.find_by(source_id: 'wamid.ruim')).to be_nil
    expect(inbox.contact_inboxes.find_by!(source_id: telefone_cliente).contact.conversations.count).to eq(1)
    expect(Message.where(source_id: %w[wamid.cliente1 wamid.escritorio1]).count).to eq(2)
  end

  it 'troca mídia sem conteúdo e tipo desconhecido por texto fixo' do
    mensagens.replace([
                        { from: telefone_cliente, id: 'wamid.midia', timestamp: '1700000000', type: 'media_placeholder' },
                        { from: telefone_cliente, id: 'wamid.estranho', timestamp: '1700000001', type: 'reaction' }
                      ])

    importar

    expect(Message.find_by(source_id: 'wamid.midia').content).to eq(I18n.t('conversations.messages.whatsapp.historico_midia'))
    expect(Message.find_by(source_id: 'wamid.estranho').content)
      .to eq(I18n.t('conversations.messages.whatsapp.historico_nao_importado', tipo: 'reaction'))
  end

  it 'importa em silêncio: sem evento no Dispatcher, sem lead, sem reenvio e sem templates' do
    allow(MessageTemplates::HookExecutionService).to receive(:new)
    channel

    expect { importar }.not_to have_enqueued_job(EventDispatcherJob)

    expect(Lead.count).to eq(0)
    expect(SendReplyJob).not_to have_been_enqueued
    expect(MessageTemplates::HookExecutionService).not_to have_received(:new)
  end

  it 'avisa no ntfy quando a fase 2 chega a 100%' do
    lote[:metadata] = { phase: 2, chunk_order: 9, progress: 100 }

    expect { importar }.to have_enqueued_job(Ramon::NtfyPushJob).with(hash_including(title: 'Historico do WhatsApp importado'))
  end

  it 'não avisa fim no meio da importação' do
    expect { importar }.not_to have_enqueued_job(Ramon::NtfyPushJob)
  end

  context 'when o escritório recusou compartilhar o histórico' do
    let(:value) { { metadata: { phone_number_id: '123456789' }, history: [{ errors: [{ code: 2_593_109, title: 'History sync is turned off' }] }] } }

    it 'grava a recusa, avisa no ntfy e não importa nada' do
      expect { importar }.to have_enqueued_job(Ramon::NtfyPushJob).with(hash_including(title: 'Historico do WhatsApp nao foi compartilhado'))

      expect(channel.reload.provider_config.dig('coexistencia', 'historico_recusado_em')).to be_present
      expect(inbox.conversations).to be_empty
    end
  end

  context 'when chega só o conteúdo de mídia (value.messages[])' do
    let(:value) { { metadata: { phone_number_id: '123456789' }, messages: [{ id: 'wamid.midia', type: 'image' }] } }

    it 'ignora nesta versão' do
      expect { importar }.not_to change(Message, :count)
    end
  end
end
