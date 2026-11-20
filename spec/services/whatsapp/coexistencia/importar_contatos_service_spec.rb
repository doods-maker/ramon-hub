require 'rails_helper'

RSpec.describe Whatsapp::Coexistencia::ImportarContatosService do
  let!(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { channel.account }

  def importar(action:, nome: 'João da Silva', telefone: '5548999992222')
    value = { metadata: { phone_number_id: '123456789' },
              state_sync: [{ type: 'contact', action: action, metadata: { timestamp: '1700000000' },
                             contact: { full_name: nome, first_name: nome.split.first, phone_number: telefone } }] }
    described_class.new(channel: channel, value: value).perform
  end

  it 'add cria o contato com nome e telefone e liga à caixa' do
    importar(action: 'add')

    contato = inbox.contact_inboxes.find_by!(source_id: '5548999992222').contact
    expect(contato).to have_attributes(name: 'João da Silva', phone_number: '+5548999992222')
  end

  it 'add completa o nome quando o atual é o telefone' do
    contato = create(:contact, account: account, name: '+5548999992222', phone_number: '+5548999992222')

    importar(action: 'add')

    expect(contato.reload.name).to eq('João da Silva')
  end

  it 'add não pisa no nome editado no hub' do
    contato = create(:contact, account: account, name: 'João (cliente auxílio-acidente)', phone_number: '+5548999992222')

    importar(action: 'add')

    expect(contato.reload.name).to eq('João (cliente auxílio-acidente)')
  end

  it 'remove não apaga nada' do
    importar(action: 'add')

    expect { importar(action: 'remove') }.not_to change(Contact, :count)
    expect(inbox.contact_inboxes.find_by(source_id: '5548999992222')).to be_present
  end

  it 'importa em silêncio' do
    expect { importar(action: 'add') }.not_to have_enqueued_job(EventDispatcherJob)
  end
end
