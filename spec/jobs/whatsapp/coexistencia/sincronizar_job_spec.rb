require 'rails_helper'

RSpec.describe Whatsapp::Coexistencia::SincronizarJob do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:phone_number_id) { channel.provider_config['phone_number_id'] }
  let(:api_client) { instance_double(Whatsapp::FacebookApiClient) }

  before do
    allow(Whatsapp::FacebookApiClient).to receive(:new).with('test_key').and_return(api_client)
    allow(api_client).to receive(:request_smb_app_data).and_return({ 'request_id' => 'req_1' })
  end

  it 'roda na fila low' do
    expect { described_class.perform_later(channel.id) }.to have_enqueued_job(described_class).with(channel.id).on_queue('low')
  end

  it 'pede os contatos e depois o histórico, e grava cada pedido' do
    described_class.perform_now(channel.id)

    expect(api_client).to have_received(:request_smb_app_data).with(phone_number_id, 'smb_app_state_sync').ordered
    expect(api_client).to have_received(:request_smb_app_data).with(phone_number_id, 'history').ordered

    coexistencia = channel.reload.provider_config['coexistencia']
    expect(coexistencia['smb_app_state_sync']['pedido_em']).to be_present
    expect(coexistencia['history']).to include('request_id' => 'req_1')
  end

  it 'não repete a sincronização que já foi pedida' do
    channel.provider_config = channel.provider_config.merge('coexistencia' => { 'smb_app_state_sync' => { 'pedido_em' => '2026-11-20T10:00:00Z' } })
    channel.save!(validate: false)

    described_class.perform_now(channel.id)

    expect(api_client).not_to have_received(:request_smb_app_data).with(phone_number_id, 'smb_app_state_sync')
    expect(api_client).to have_received(:request_smb_app_data).with(phone_number_id, 'history')
  end

  it 'erro HTTP definitivo da Meta (4xx) não grava, avisa no ntfy uma vez e para' do
    allow(api_client).to receive(:request_smb_app_data).and_raise(RuntimeError, 'SMB app data sync failed: {"error":"x"}')

    expect { described_class.perform_now(channel.id) }
      .to have_enqueued_job(Ramon::NtfyPushJob).with(hash_including(title: 'Sincronizacao do WhatsApp falhou')).exactly(:once)

    expect(api_client).to have_received(:request_smb_app_data).once
    expect(channel.reload.provider_config['coexistencia']).to be_blank
  end

  it 'erro passageiro da Meta (429/5xx) não grava e tenta de novo' do
    allow(api_client).to receive(:request_smb_app_data).and_raise(Whatsapp::Coexistencia::ErroTransitorio, 'SMB app data sync failed (503)')

    expect { described_class.perform_now(channel.id) }.to have_enqueued_job(described_class).with(channel.id)
    expect(channel.reload.provider_config['coexistencia']).to be_blank
  end

  it 'tenta de novo quando a rede cai' do
    allow(api_client).to receive(:request_smb_app_data).and_raise(Net::OpenTimeout)

    expect { described_class.perform_now(channel.id) }.to have_enqueued_job(described_class).with(channel.id)
    expect(channel.reload.provider_config['coexistencia']).to be_blank
  end

  it 'nunca pede para canal que não veio do Embedded Signup' do
    channel.provider_config = channel.provider_config.merge('source' => 'manual')
    channel.save!(validate: false)

    described_class.perform_now(channel.id)

    expect(api_client).not_to have_received(:request_smb_app_data)
  end

  it 'não pede quando o webhook falhou e o canal pede reautorização, e avisa no ntfy' do
    channel.prompt_reauthorization!

    expect { described_class.perform_now(channel.id) }
      .to have_enqueued_job(Ramon::NtfyPushJob).with(hash_including(title: 'Sincronizacao do WhatsApp nao pedida'))

    expect(api_client).not_to have_received(:request_smb_app_data)
  end
end
