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
end
