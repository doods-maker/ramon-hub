require 'rails_helper'

RSpec.describe Ramon::NotionEspelhoJob do
  let(:peca) { create(:peca, notion_page_id: 'pg1') }
  let(:url) { 'https://api.notion.com/v1/pages/pg1' }

  it 'não chama o Notion sem token' do
    with_modified_env(RAMON_NOTION_TOKEN: nil) { described_class.perform_now(peca.id) }
    expect(a_request(:patch, url)).not_to have_been_made
  end

  it 'agendado aparece como montado' do
    peca.update_columns(status: 'agendado') # rubocop:disable Rails/SkipsModelValidations
    stub = stub_request(:patch, url)
           .with(body: { properties: { 'Status' => { select: { name: 'montado' } } } }.to_json,
                 headers: { 'Authorization' => 'Bearer nt', 'Notion-Version' => '2022-06-28' })
           .to_return(status: 200)
    with_modified_env(RAMON_NOTION_TOKEN: 'nt') { described_class.perform_now(peca.id) }
    expect(stub).to have_been_requested
  end

  it 'montando não é espelhado (senão o vigia local monta junto)' do
    peca.update_columns(status: 'montando') # rubocop:disable Rails/SkipsModelValidations
    with_modified_env(RAMON_NOTION_TOKEN: 'nt') { described_class.perform_now(peca.id) }
    expect(a_request(:patch, url)).not_to have_been_made
  end

  it 'erro do Notion não levanta' do
    stub_request(:patch, url).to_return(status: 500)
    with_modified_env(RAMON_NOTION_TOKEN: 'nt') { expect { described_class.perform_now(peca.id) }.not_to raise_error }
  end
end
