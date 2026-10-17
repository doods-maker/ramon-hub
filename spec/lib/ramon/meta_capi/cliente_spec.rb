require 'rails_helper'

RSpec.describe Ramon::MetaCapi::Cliente do
  let(:cliente) { described_class.new(token: 'tok', waba_id: 'waba1') }
  let(:base) { 'https://graph.facebook.com/v24.0' }

  def json(corpo, status = 200)
    { status: status, body: corpo.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def enviar(**extra)
    cliente.enviar(evento: 'LeadSubmitted', event_id: 'lead-1-LeadSubmitted', event_time: 1_760_000_000, ctwa_clid: 'clid1', **extra)
  end

  describe '#enviar' do
    around { |ex| with_modified_env(RAMON_META_DATASET_ID: 'ds1') { ex.run } }

    it 'manda JSON com os campos do funil e nada além deles' do
      stub = stub_request(:post, "#{base}/ds1/events").with do |req|
        corpo = JSON.parse(req.body)
        item = corpo['data'].first
        expect(req.headers['Content-Type']).to eq('application/json')
        expect(corpo['access_token']).to eq('tok')
        expect(corpo).not_to have_key('test_event_code')
        expect(item).to include('event_name' => 'LeadSubmitted', 'event_id' => 'lead-1-LeadSubmitted', 'event_time' => 1_760_000_000,
                                'action_source' => 'business_messaging', 'messaging_channel' => 'whatsapp',
                                'user_data' => { 'whatsapp_business_account_id' => 'waba1', 'ctwa_clid' => 'clid1' })
        true
      end.to_return(json(events_received: 1))
      expect(enviar).to be(true)
      expect(stub).to have_been_requested
    end

    it 'sem value, custom_data não traz value nem currency' do
      stub_request(:post, "#{base}/ds1/events").with do |req|
        expect(JSON.parse(req.body)['data'].first['custom_data']).to eq({})
        true
      end.to_return(json({}))
      enviar
    end

    it 'com value e test_event_code, manda currency BRL, value e o código' do
      stub_request(:post, "#{base}/ds1/events").with do |req|
        corpo = JSON.parse(req.body)
        expect(corpo['data'].first['custom_data']).to eq('currency' => 'BRL', 'value' => 1500.0)
        expect(corpo['test_event_code']).to eq('TEST1')
        true
      end.to_return(json({}))
      enviar(value: 1500.0, test_event_code: 'TEST1')
    end

    it '503 vira Transitorio' do
      stub_request(:post, "#{base}/ds1/events").to_return(json({}, 503))
      expect { enviar }.to raise_error(Ramon::MetaCapi::Transitorio)
    end

    it '429 vira Transitorio' do
      stub_request(:post, "#{base}/ds1/events").to_return(json({}, 429))
      expect { enviar }.to raise_error(Ramon::MetaCapi::Transitorio)
    end

    it 'falha de rede vira Transitorio' do
      stub_request(:post, "#{base}/ds1/events").to_timeout
      expect { enviar }.to raise_error(Ramon::MetaCapi::Transitorio)
    end

    it '400 vira Recusado com HTTP e error.code, sem a mensagem da Meta' do
      stub_request(:post, "#{base}/ds1/events").to_return(json({ error: { code: 100, message: 'segredo do cliente' } }, 400))
      expect { enviar }.to raise_error(Ramon::MetaCapi::Recusado) { |e|
        expect(e.message).to include('400', '100')
        expect(e.message).not_to include('segredo')
      }
    end

    it 'usa o host de WHATSAPP_CLOUD_BASE_URL' do
      with_modified_env(WHATSAPP_CLOUD_BASE_URL: 'https://meta.exemplo.test') do
        stub = stub_request(:post, 'https://meta.exemplo.test/v24.0/ds1/events').to_return(json({}))
        enviar
        expect(stub).to have_been_requested
      end
    end
  end

  describe '#dataset_id' do
    it 'com a env, não chama a Graph API' do
      with_modified_env(RAMON_META_DATASET_ID: 'ds9') { expect(cliente.dataset_id).to eq('ds9') }
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end

    context 'without the env' do
      around { |ex| with_modified_env(RAMON_META_DATASET_ID: nil) { ex.run } }

      it 'lê o dataset da WABA' do
        stub_request(:get, "#{base}/waba1/dataset").with(headers: { 'Authorization' => 'Bearer tok' })
                                                   .to_return(json(data: [{ dataset_id: 'dsX' }]))
        expect(cliente.dataset_id).to eq('dsX')
      end

      it 'com lista vazia, cria o dataset por POST' do
        stub_request(:get, "#{base}/waba1/dataset").with(headers: { 'Authorization' => 'Bearer tok' }).to_return(json(data: []))
        post = stub_request(:post, "#{base}/waba1/dataset").to_return(json(id: 'dsNovo'))
        expect(cliente.dataset_id).to eq('dsNovo')
        expect(post).to have_been_requested
      end
    end
  end
end
