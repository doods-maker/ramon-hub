require 'rails_helper'

RSpec.describe Ramon::IgTokenRefreshJob do
  let(:url) { 'https://graph.instagram.com/refresh_access_token' }

  before { InstallationConfig.create!(name: 'RAMON_IG_PUBLISH_TOKEN', value: 'velho', locked: false) }

  it 'grava o token renovado' do
    stub_request(:get, url).with(query: { grant_type: 'ig_refresh_token', access_token: 'velho' })
                           .to_return(body: { access_token: 'novo', expires_in: 5_184_000 }.to_json)
    described_class.perform_now
    expect(InstallationConfig.find_by(name: 'RAMON_IG_PUBLISH_TOKEN').value).to eq 'novo'
  end

  it 'avisa no celular quando a Meta recusa' do
    stub_request(:get, url).with(query: hash_including({})).to_return(status: 400, body: { error: { message: 'expired' } }.to_json)
    expect { described_class.perform_now }.to have_enqueued_job(Ramon::NtfyPushJob)
    expect(InstallationConfig.find_by(name: 'RAMON_IG_PUBLISH_TOKEN').value).to eq 'velho'
  end

  context 'with a caixa do Instagram' do
    let(:vence_em) { 5.days.from_now }
    # a factory chama access_token ao criar: nasce com folga e só depois recebe o vencimento do teste
    let!(:canal) do
      create(:channel_instagram, access_token: 'caixa_velho').tap { |c| c.update!(expires_at: vence_em, updated_at: 25.hours.ago) }
    end

    before do
      stub_request(:get, url).with(query: { grant_type: 'ig_refresh_token', access_token: 'velho' })
                             .to_return(body: { access_token: 'novo', expires_in: 5_184_000 }.to_json)
    end

    it 'renova o token da caixa perto de vencer, mesmo sem uso' do
      stub_request(:get, url).with(query: { grant_type: 'ig_refresh_token', access_token: 'caixa_velho' })
                             .to_return(body: { access_token: 'caixa_novo', expires_in: 5_184_000 }.to_json)
      expect { described_class.perform_now }.not_to have_enqueued_job(Ramon::NtfyPushJob)
      expect(canal.reload[:access_token]).to eq 'caixa_novo'
      expect(canal.expires_at).to be > 50.days.from_now
    end

    it 'avisa no celular quando a caixa não renova, sem travar a publicação' do
      stub_request(:get, url).with(query: hash_including(access_token: 'caixa_velho')).to_return(status: 400, body: '{}')
      expect { described_class.perform_now }.to have_enqueued_job(Ramon::NtfyPushJob).once
      expect(canal.reload[:access_token]).to eq 'caixa_velho'
      expect(InstallationConfig.find_by(name: 'RAMON_IG_PUBLISH_TOKEN').value).to eq 'novo'
    end

    context 'with folga' do
      let(:vence_em) { 30.days.from_now }

      it 'não chama a Meta nem avisa' do
        expect { described_class.perform_now }.not_to have_enqueued_job(Ramon::NtfyPushJob)
        expect(a_request(:get, url).with(query: hash_including(access_token: 'caixa_velho'))).not_to have_been_made
      end
    end

    context 'with o token já vencido' do
      let(:vence_em) { 1.day.ago }

      it 'avisa para reconectar, sem chamar a Meta' do
        expect { described_class.perform_now }.to have_enqueued_job(Ramon::NtfyPushJob).once
        expect(a_request(:get, url).with(query: hash_including(access_token: 'caixa_velho'))).not_to have_been_made
      end
    end
  end
end
