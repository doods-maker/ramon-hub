require 'rails_helper'

RSpec.describe Ramon::MetaCapi::Insights do
  let(:insights) { described_class.new(token: 'tok', ad_account_id: '123') }
  let(:url) { 'https://graph.facebook.com/v24.0/act_123/insights' }

  def json(corpo, status = 200)
    { status: status, body: corpo.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def item(ad_id, dia, spend = '10.50')
    { ad_id: ad_id, ad_name: "Anuncio #{ad_id}", campaign_id: 'c1', campaign_name: 'Camp', spend: spend,
      impressions: '1000', clicks: '12', date_start: dia }
  end

  describe '#por_anuncio' do
    it 'segue paging.next, manda o token no header e devolve os tipos certos' do
      proxima = "#{url}?after=abc&access_token=tok"
      stub_request(:get, url).with(query: hash_including('level' => 'ad', 'time_increment' => '1'),
                                   headers: { 'Authorization' => 'Bearer tok' })
                             .to_return(json(data: [item('a1', '2026-10-14')], paging: { next: proxima }))
      stub_request(:get, proxima).with(headers: { 'Authorization' => 'Bearer tok' })
                                 .to_return(json(data: [item('a2', '2026-10-15')]))

      linhas = insights.por_anuncio(desde: Date.new(2026, 10, 14), ate: Date.new(2026, 10, 15))

      expect(linhas.map { |l| l[:ad_id] }).to eq(%w[a1 a2])
      expect(linhas.first).to include(data: Date.new(2026, 10, 14), spend: BigDecimal('10.50'), impressions: 1000, clicks: 12)
    end

    it 'transforma 429 em Transitorio e 400 em Recusado com HTTP e code' do
      stub_request(:get, url).with(query: hash_including({})).to_return(json({}, 429)).then
                             .to_return(json({ error: { code: 190 } }, 400))
      expect { insights.por_anuncio(desde: Date.current, ate: Date.current) }.to raise_error(Ramon::MetaCapi::Transitorio)
      expect { insights.por_anuncio(desde: Date.current, ate: Date.current) }
        .to raise_error(Ramon::MetaCapi::Recusado) { |e| expect([e.http, e.codigo]).to eq([400, 190]) }
    end
  end
end
