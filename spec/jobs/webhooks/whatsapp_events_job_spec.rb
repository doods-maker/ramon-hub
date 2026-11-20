require 'rails_helper'

RSpec.describe Webhooks::WhatsappEventsJob do
  subject(:job) { described_class }

  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:params)  do
    {
      object: 'whatsapp_business_account',
      phone_number: channel.phone_number,
      entry: [{
        changes: [
          {
            value: {
              metadata: {
                phone_number_id: channel.provider_config['phone_number_id'],
                display_phone_number: channel.phone_number.delete('+')
              }
            }
          }
        ]
      }]
    }
  end
  let(:process_service) { double }

  before do
    allow(process_service).to receive(:perform)
  end

  it 'enqueues the job' do
    expect { job.perform_later(params) }.to have_enqueued_job(described_class)
      .with(params)
      .on_queue('low')
  end

  context 'when whatsapp_cloud provider' do
    it 'enqueue Whatsapp::IncomingMessageWhatsappCloudService' do
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new)
      job.perform_now(params)
    end

    it 'will not enqueue message jobs based on phone number in the URL if the entry payload is not present' do
      params = {
        object: 'whatsapp_business_account',
        phone_number: channel.phone_number,
        entry: [{ changes: [{}] }]
      }
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new)
      allow(Whatsapp::IncomingMessageService).to receive(:new)

      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
      expect(Whatsapp::IncomingMessageService).not_to receive(:new)
      job.perform_now(params)
    end

    it 'will not enqueue Whatsapp::IncomingMessageWhatsappCloudService if channel reauthorization required' do
      channel.prompt_reauthorization!
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
      job.perform_now(params)
    end

    it 'still enqueues for manual channels even when reauthorization required' do
      channel.update!(provider_config: channel.provider_config.merge('source' => 'manual'))
      channel.prompt_reauthorization!
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new)
      job.perform_now(params)
    end

    it 'will not enqueue if channel is not present' do
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(process_service)

      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
      expect(Whatsapp::IncomingMessageService).not_to receive(:new)
      job.perform_now(phone_number: 'random_phone_number')
    end

    it 'will not enqueue Whatsapp::IncomingMessageWhatsappCloudService if account is suspended' do
      account = channel.account
      account.update!(status: :suspended)
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(process_service)

      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
      expect(Whatsapp::IncomingMessageService).not_to receive(:new)
      job.perform_now(params)
    end

    it 'logs a warning when channel is inactive' do
      channel.prompt_reauthorization!
      allow(Rails.logger).to receive(:warn)

      expect(Rails.logger).to receive(:warn).with("Inactive WhatsApp channel: #{channel.phone_number}")
      job.perform_now(params)
    end

    it 'logs a warning with unknown phone number when channel does not exist' do
      unknown_phone = '+1234567890'
      allow(Rails.logger).to receive(:warn)

      expect(Rails.logger).to receive(:warn).with("Inactive WhatsApp channel: unknown - #{unknown_phone}")
      job.perform_now(phone_number: unknown_phone)
    end

    it 'uses from_user_id as the mutex sender for BSUID-only inbound messages' do
      bsuid = 'IN.2081978709342942'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:value][:messages] = [
        { from: '', from_user_id: bsuid, id: 'wamid-test', text: { body: 'Hello' }, type: 'text' }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'prefers from_user_id as the mutex sender for mixed phone and BSUID inbound messages' do
      bsuid = 'IN.2081978709342942'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:value][:messages] = [
        { from: '919745786257', from_user_id: bsuid, id: 'wamid-test', text: { body: 'Hello' }, type: 'text' }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'uses contact user_id as the mutex sender when message from_user_id is missing' do
      bsuid = 'IN.2081978709342942'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:value][:contacts] = [
        { profile: { name: 'Muhsin' }, wa_id: '919745786257', user_id: bsuid }
      ]
      wb_params[:entry].first[:changes].first[:value][:messages] = [
        { from: '919745786257', id: 'wamid-test', text: { body: 'Hello' }, type: 'text' }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'prefers parent BSUID as the mutex sender for inbound messages with both identifiers' do
      bsuid = 'IN.2081978709342942'
      parent_bsuid = 'IN.ENT.9081726354'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:value][:contacts] = [
        { profile: { name: 'Muhsin' }, user_id: bsuid, parent_user_id: parent_bsuid }
      ]
      wb_params[:entry].first[:changes].first[:value][:messages] = [
        { from_user_id: bsuid, from_parent_user_id: parent_bsuid, id: 'wamid-test', text: { body: 'Hello' }, type: 'text' }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: parent_bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'uses to_user_id as the mutex sender for BSUID-only echo messages' do
      bsuid = 'IN.2081978709342942'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:field] = 'smb_message_echoes'
      wb_params[:entry].first[:changes].first[:value][:message_echoes] = [
        { from: channel.phone_number.delete('+'), to: '', to_user_id: bsuid, id: 'wamid-test', text: { body: 'Hello' }, type: 'text' }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'prefers parent BSUID as the mutex sender for echo messages with both identifiers' do
      bsuid = 'IN.2081978709342942'
      parent_bsuid = 'IN.ENT.9081726354'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:field] = 'smb_message_echoes'
      wb_params[:entry].first[:changes].first[:value][:message_echoes] = [
        {
          from: channel.phone_number.delete('+'), to: '919745786257', to_user_id: bsuid, to_parent_user_id: parent_bsuid,
          id: 'wamid-test', text: { body: 'Hello' }, type: 'text'
        }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: parent_bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'prefers to_user_id as the mutex sender for mixed phone and BSUID echo messages' do
      bsuid = 'IN.2081978709342942'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:field] = 'smb_message_echoes'
      wb_params[:entry].first[:changes].first[:value][:message_echoes] = [
        { from: channel.phone_number.delete('+'), to: '919745786257', to_user_id: bsuid, id: 'wamid-test', text: { body: 'Hello' },
          type: 'text' }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'uses the current identifier as the mutex sender for identity-change system messages' do
      current_bsuid = 'IN.7391028465738291'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:value].delete(:contacts)
      wb_params[:entry].first[:changes].first[:value][:messages] = [
        {
          id: 'wamid-system', type: 'system',
          system: { type: 'user_changed_user_id', previous_user_id: 'IN.2081978709342942', user_id: current_bsuid }
        }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: current_bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'passes the actual mixed-batch mutex sender to identity rotation processing' do
      current_bsuid = 'IN.CURRENTBSUID'
      current_parent_bsuid = 'IN.ENT.CURRENTBSUID'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:value][:contacts] = [{ user_id: current_bsuid }]
      wb_params[:entry].first[:changes].first[:value][:messages] = [
        { from_user_id: current_bsuid, id: 'wamid-message', text: { body: 'Hello' }, type: 'text' },
        {
          id: 'wamid-system', type: 'system',
          system: {
            type: 'user_changed_user_id', previous_user_id: 'IN.PREVIOUSBSUID', user_id: current_bsuid,
            previous_parent_user_id: 'IN.ENT.PREVIOUSBSUID', parent_user_id: current_parent_bsuid
          }
        }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: current_bsuid)

      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield
      expect(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new)
        .with(inbox: channel.inbox, params: wb_params, locked_sender_id: current_bsuid)
        .and_return(process_service)

      job_instance.perform(wb_params)
    end
  end

  context 'when default provider' do
    it 'enqueue Whatsapp::IncomingMessageService' do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      channel.update(provider: 'default')
      allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageService).to receive(:new)
      job.perform_now(params)
    end
  end

  context 'when whatsapp business params' do
    it 'enqueue Whatsapp::IncomingMessageWhatsappCloudService based on the number in payload' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [
          {
            changes: [
              {
                value: {
                  metadata: {
                    phone_number_id: other_channel.provider_config['phone_number_id'],
                    display_phone_number: other_channel.phone_number.delete('+')
                  }
                }
              }
            ]
          }
        ]
      }
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).with(inbox: other_channel.inbox, params: wb_params)
      job.perform_now(wb_params)
    end

    it 'Ignore reaction type message and stop raising error' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              contacts: [{ profile: { name: 'Test Test' }, wa_id: '1111981136571' }],
              messages: [{
                from: '1111981136571', reaction: { emoji: '👍' }, timestamp: '1664799904', type: 'reaction'
              }],
              metadata: {
                phone_number_id: other_channel.provider_config['phone_number_id'],
                display_phone_number: other_channel.phone_number.delete('+')
              }
            }
          }]
        }]
      }.with_indifferent_access
      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: other_channel.inbox, params: wb_params).perform
      end.not_to change(Message, :count)
    end

    it 'ignore reaction type message, would not create contact if the reaction is the first event' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              contacts: [{ profile: { name: 'Test Test' }, wa_id: '1111981136571' }],
              messages: [{
                from: '1111981136571', reaction: { emoji: '👍' }, timestamp: '1664799904', type: 'reaction'
              }],
              metadata: {
                phone_number_id: other_channel.provider_config['phone_number_id'],
                display_phone_number: other_channel.phone_number.delete('+')
              }
            }
          }]
        }]
      }.with_indifferent_access
      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: other_channel.inbox, params: wb_params).perform
      end.not_to change(Contact, :count)
    end

    it 'ignore request_welcome type message, would not create contact or conversation' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              messages: [{
                from: '1111981136571', timestamp: '1664799904', type: 'request_welcome'
              }],
              metadata: {
                phone_number_id: other_channel.provider_config['phone_number_id'],
                display_phone_number: other_channel.phone_number.delete('+')
              }
            }
          }]
        }]
      }.with_indifferent_access
      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: other_channel.inbox, params: wb_params).perform
      end.not_to change(Contact, :count)

      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: other_channel.inbox, params: wb_params).perform
      end.not_to change(Conversation, :count)
    end

    it 'will not enque Whatsapp::IncomingMessageWhatsappCloudService when invalid phone number id' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [
          {
            changes: [
              {
                value: {
                  metadata: {
                    phone_number_id: 'random phone number id',
                    display_phone_number: other_channel.phone_number.delete('+')
                  }
                }
              }
            ]
          }
        ]
      }
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new).with(inbox: other_channel.inbox, params: wb_params)
      job.perform_now(wb_params)
    end
  end

  context 'with coexistence sync webhooks' do
    let(:importador) { instance_double(Whatsapp::Coexistencia::ImportarHistoricoService, perform: true) }
    let(:importador_contatos) { instance_double(Whatsapp::Coexistencia::ImportarContatosService, perform: true) }

    def coexistence_params(field, extra_value)
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:field] = field
      wb_params[:entry].first[:changes].first[:value].merge!(extra_value)
      wb_params
    end

    it 'routes history to the silent history importer, never to the incoming message flow or the sender lock' do
      wb_params = coexistence_params('history', history: [{ metadata: { phase: 0, chunk_order: 1, progress: 10 }, threads: [] }],
                                                messages: [{ from: '5548999991111', id: 'wamid.midia', type: 'image' }])
      job_instance = described_class.new
      allow(Whatsapp::Coexistencia::ImportarHistoricoService).to receive(:new).and_return(importador)
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new)
      allow(job_instance).to receive(:with_lock)

      job_instance.perform(wb_params)

      expect(Whatsapp::Coexistencia::ImportarHistoricoService).to have_received(:new)
        .with(channel: channel, value: wb_params[:entry].first[:changes].first[:value])
      expect(importador).to have_received(:perform)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to have_received(:new)
      expect(job_instance).not_to have_received(:with_lock)
    end

    it 'routes smb_app_state_sync to the silent contacts importer' do
      wb_params = coexistence_params('smb_app_state_sync',
                                     state_sync: [{ type: 'contact', action: 'add', contact: { phone_number: '5548999992222' } }])
      allow(Whatsapp::Coexistencia::ImportarContatosService).to receive(:new).and_return(importador_contatos)
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new)

      job.perform_now(wb_params)

      expect(Whatsapp::Coexistencia::ImportarContatosService).to have_received(:new)
        .with(channel: channel, value: wb_params[:entry].first[:changes].first[:value])
      expect(importador_contatos).to have_received(:perform)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to have_received(:new)
    end

    context 'with account_update (no metadata in the payload)' do
      def account_update_params(value, entry_id: 'partner_portfolio_1')
        { object: 'whatsapp_business_account', phone_number: channel.phone_number,
          entry: [{ id: entry_id, changes: [{ field: 'account_update', value: value }] }] }
      end

      it 'records PARTNER_REMOVED on the channel found by WABA id and pushes ntfy, without prompting reauthorization' do
        wb_params = account_update_params(
          event: 'PARTNER_REMOVED',
          waba_info: { waba_id: channel.provider_config['business_account_id'], owner_business_id: 'owner_1' },
          disconnection_info: { reason: 'PRIMARY_INACTIVITY', initiated_by: 'SYSTEM' }
        )

        expect { job.perform_now(wb_params) }
          .to have_enqueued_job(Ramon::NtfyPushJob).with(hash_including(title: 'WhatsApp desconectado do hub'))

        channel.reload
        expect(channel.provider_config['coexistencia']).to include('motivo' => 'PRIMARY_INACTIVITY', 'iniciado_por' => 'SYSTEM')
        expect(channel.provider_config.dig('coexistencia', 'desconectado_em')).to be_present
        expect(channel.reauthorization_required?).to be(false)
      end

      it 'clears the disconnection on ACCOUNT_RECONNECTED (WABA id in entry[0].id)' do
        channel.provider_config = channel.provider_config.merge('coexistencia' => { 'desconectado_em' => '2026-11-20T10:00:00Z' })
        channel.save!(validate: false)

        job.perform_now(account_update_params({ event: 'ACCOUNT_RECONNECTED' }, entry_id: channel.provider_config['business_account_id']))

        expect(channel.reload.provider_config.dig('coexistencia', 'desconectado_em')).to be_nil
      end

      it 'only logs other events' do
        wb_params = account_update_params({ event: 'VERIFIED_ACCOUNT' }, entry_id: channel.provider_config['business_account_id'])

        expect { job.perform_now(wb_params) }.not_to have_enqueued_job(Ramon::NtfyPushJob)
        expect(channel.reload.provider_config['coexistencia']).to be_blank
      end
    end
  end
end
