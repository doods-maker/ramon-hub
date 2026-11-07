require 'rails_helper'

RSpec.describe Ramon::PecaMetricasJob do
  let(:url) { %r{graph\.instagram\.com/v26\.0/m1/insights} }
  let!(:peca) { create(:peca, status: 'publicado', ig_media_id: 'm1', agendado_para: 3.days.ago) }

  before { InstallationConfig.create!(name: 'RAMON_IG_PUBLISH_TOKEN', value: 'tk', locked: false) }

  it 'com a chave off não chama o Instagram' do
    described_class.perform_now
    expect(a_request(:get, url)).not_to have_been_made
  end

  it 'grava as métricas da peça publicada e pula as antigas' do
    antiga = create(:peca, status: 'publicado', ig_media_id: 'm2', agendado_para: 90.days.ago)
    stub_request(:get, url).with(query: hash_including('metric' => 'reach,saved,shares,likes,comments')).to_return(
      body: { data: [{ name: 'reach', values: [{ value: 611 }] }, { name: 'saved', total_value: { value: 9 } },
                     { name: 'shares', values: [{ value: 4 }] }] }.to_json
    )

    with_modified_env(RAMON_IG_INSIGHTS: 'on') { described_class.perform_now }

    expect(peca.reload).to have_attributes(alcance: 611, salvamentos: 9, compartilhamentos: 4)
    expect(peca.metricas_em).to be_present
    expect(antiga.reload.metricas_em).to be_nil
  end

  it 'timeout numa peça não impede as outras' do
    outra = create(:peca, status: 'publicado', ig_media_id: 'm3', agendado_para: 2.days.ago)
    stub_request(:get, url).to_timeout
    stub_request(:get, %r{/m3/insights}).to_return(body: { data: [{ name: 'reach', values: [{ value: 7 }] }] }.to_json)
    with_modified_env(RAMON_IG_INSIGHTS: 'on') { described_class.perform_now }
    expect(outra.reload.alcance).to eq(7)
  end

  it 'erro da Meta numa peça não derruba o job' do
    stub_request(:get, url).to_return(status: 400, body: { error: { message: 'sem permissão' } }.to_json)
    expect { with_modified_env(RAMON_IG_INSIGHTS: 'on') { described_class.perform_now } }.not_to raise_error
    expect(peca.reload.metricas_em).to be_nil
  end
end
