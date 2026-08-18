require 'rails_helper'

RSpec.describe Ramon::ZapsignClient do
  describe '.templates' do
    let(:page1) do
      { 'count' => 2,
        'next' => 'https://api.zapsign.com.br/api/v1/templates/?page=2',
        'results' => [{ 'token' => 't1', 'name' => 'Aux. Acidente', 'active' => true },
                      { 'token' => 'x', 'name' => 'Velho', 'active' => false }] }
    end
    let(:page2) do
      { 'count' => 2, 'next' => nil, 'results' => [{ 'token' => 't2', 'name' => 'Aposentadoria', 'active' => true }] }
    end

    it 'devolve só ativos, todas as páginas, com token e nome' do
      with_modified_env(ZAPSIGN_API_TOKEN: 'z') do
        Rails.cache.clear
        allow(HTTParty).to receive(:get).with("#{described_class::BASE}/templates/", hash_including(query: { page: 1 }))
                                        .and_return(instance_double(HTTParty::Response, success?: true, code: 200, parsed_response: page1))
        allow(HTTParty).to receive(:get).with("#{described_class::BASE}/templates/", hash_including(query: { page: 2 }))
                                        .and_return(instance_double(HTTParty::Response, success?: true, code: 200, parsed_response: page2))
        expect(described_class.templates).to eq([{ 'token' => 't1', 'name' => 'Aux. Acidente' }, { 'token' => 't2', 'name' => 'Aposentadoria' }])
      end
    end

    it 'levanta UnavailableError sem token' do
      with_modified_env(ZAPSIGN_API_TOKEN: nil) { expect { described_class.templates }.to raise_error(Ramon::ZapsignClient::UnavailableError) }
    end
  end
end
