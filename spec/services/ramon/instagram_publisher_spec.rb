require 'rails_helper'

RSpec.describe Ramon::InstagramPublisher do
  let(:g) { 'https://graph.instagram.com/v26.0' }
  let(:peca) do
    build(:peca, tipo: 'carrossel', imagens: %w[https://m/1.jpg https://m/2.jpg],
                 legenda: "Texto\n\nCom Brenda Antunes, nossa advogada")
  end
  let(:pub) { described_class.new(peca, token: 'tk', espera: 0) }

  it 'publica carrossel: filhos, contêiner com colaborador, espera FINISHED e media_publish' do
    filhos = stub_request(:post, "#{g}/me/media").with(body: hash_including('is_carousel_item' => 'true'))
                                                 .to_return({ body: { id: 'c1' }.to_json }, { body: { id: 'c2' }.to_json })
    pai = stub_request(:post, "#{g}/me/media")
          .with(body: hash_including('media_type' => 'CAROUSEL', 'children' => 'c1,c2', 'collaborators' => '["brendantunes"]'))
          .to_return(body: { id: 'p1' }.to_json)
    stub_request(:get, "#{g}/p1").with(query: hash_including('fields' => 'status_code'))
                                 .to_return({ body: { status_code: 'IN_PROGRESS' }.to_json }, { body: { status_code: 'FINISHED' }.to_json })
    publish = stub_request(:post, "#{g}/me/media_publish").with(body: hash_including('creation_id' => 'p1'))
                                                          .to_return(body: { id: 'm9' }.to_json)
    expect(pub.publicar).to eq 'm9'
    expect([filhos, pai, publish]).to all(have_been_requested.at_least_once)
    expect(a_request(:post, "#{g}/me/media").with(body: hash_including('media_type' => 'STORIES'))).not_to have_been_made
  end

  it 'estático usa image_url no contêiner único' do
    peca.assign_attributes(tipo: 'estatico', imagens: ['https://m/1.jpg'], legenda: 'L')
    stub_request(:post, "#{g}/me/media").with(body: hash_including('image_url' => 'https://m/1.jpg', 'caption' => 'L'))
                                        .to_return(body: { id: 'p1' }.to_json)
    stub_request(:get, "#{g}/p1").with(query: hash_including('fields' => 'status_code')).to_return(body: { status_code: 'FINISHED' }.to_json)
    stub_request(:post, "#{g}/me/media_publish").to_return(body: { id: 'm1' }.to_json)
    expect(pub.publicar).to eq 'm1'
  end

  it 'erro da Meta vira Erro com a mensagem' do
    stub_request(:post, "#{g}/me/media").to_return(status: 400, body: { error: { message: 'Invalid image' } }.to_json)
    expect { pub.publicar }.to raise_error(described_class::Erro, /Invalid image/)
  end

  it 'corpo não-JSON (502 HTML) vira Erro com o código HTTP, sem texto de parser' do
    stub_request(:post, "#{g}/me/media").to_return(status: 502, body: '<html>Bad Gateway</html>')
    expect { pub.publicar }.to raise_error(described_class::Erro, /HTTP 502/)
  end

  it 'falha no media_publish avisa que pode ter ido ao ar' do
    stub_request(:post, "#{g}/me/media").to_return({ body: { id: 'c1' }.to_json }, { body: { id: 'c2' }.to_json }, { body: { id: 'p1' }.to_json })
    stub_request(:get, "#{g}/p1").with(query: hash_including('fields' => 'status_code')).to_return(body: { status_code: 'FINISHED' }.to_json)
    stub_request(:post, "#{g}/me/media_publish").to_return(status: 500, body: 'oops')
    expect { pub.publicar }.to raise_error(described_class::Erro, /conferir no Instagram/)
  end

  it 'sem token não chama a Meta' do
    expect { described_class.new(peca, token: nil).publicar }.to raise_error(described_class::Erro, /token/i)
  end

  it 'permalink nunca levanta' do
    stub_request(:get, "#{g}/m9").with(query: hash_including('fields' => 'permalink')).to_return(status: 500)
    expect(pub.permalink('m9')).to be_nil
  end
end
