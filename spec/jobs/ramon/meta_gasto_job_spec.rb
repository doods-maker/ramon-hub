require 'rails_helper'

RSpec.describe Ramon::MetaGastoJob do
  let(:account) { create(:account) }
  let(:url) { 'https://graph.facebook.com/v24.0/act_123/insights' }
  let(:env) do
    { RAMON_META_GASTO: 'on', RAMON_META_AD_ACCOUNT_ID: '123', RAMON_META_ADS_TOKEN: 'tok', RAMON_META_ACCOUNT_ID: account.id.to_s }
  end

  def json(corpo)
    { status: 200, body: corpo.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def item(ad_id, dia, spend)
    { ad_id: ad_id, ad_name: 'Anuncio', campaign_id: 'c1', campaign_name: 'Camp', spend: spend,
      impressions: '1000', clicks: '12', date_start: dia }
  end

  it 'com a chave off não chama a Meta nem grava' do
    with_modified_env(env.merge(RAMON_META_GASTO: 'off')) { described_class.perform_now }
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    expect(MetaGasto.count).to eq(0)
  end

  it 'grava as linhas das duas páginas' do
    proxima = "#{url}?after=abc&access_token=tok"
    stub_request(:get, url).with(query: hash_including('level' => 'ad'))
                           .to_return(json(data: [item('a1', '2026-10-14', '10.50')], paging: { next: proxima }))
    stub_request(:get, proxima).to_return(json(data: [item('a2', '2026-10-14', '3.00')]))

    with_modified_env(env) { described_class.perform_now }

    expect(MetaGasto.where(account_id: account.id).pluck(:ad_id)).to match_array(%w[a1 a2])
  end

  it 'relê a mesma data com spend novo: atualiza e não duplica' do
    stub_request(:get, url).with(query: hash_including('level' => 'ad'))
                           .to_return(json(data: [item('a1', '2026-10-14', '10.50')])).then
                           .to_return(json(data: [item('a1', '2026-10-14', '12.00')]))

    with_modified_env(env) { 2.times { described_class.perform_now } }

    expect(MetaGasto.count).to eq(1)
    expect(MetaGasto.first.spend).to eq(BigDecimal('12.00'))
  end
end
