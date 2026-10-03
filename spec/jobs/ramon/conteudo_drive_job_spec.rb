require 'rails_helper'

RSpec.describe Ramon::ConteudoDriveJob do
  let(:peca) { create(:peca, status: 'publicado', imagens: ['https://m/01/slide-01.jpg?v=1'], legenda: 'Leg') }

  it 'não faz nada sem Drive configurado' do
    with_modified_env(RAMON_DRIVE_POSTS_ID: nil) { described_class.perform_now(peca.id) }
    expect(peca.reload.drive_pasta_id).to be_nil
  end

  it 'sobe imagens e legenda na pasta da peça' do
    allow(Ramon::DriveClient).to receive(:configured?).and_return(true)
    allow(Ramon::DriveClient).to receive(:ensure_folder).and_return('tipo1', 'pasta1')
    allow(Ramon::DriveClient).to receive(:upload).and_return('f1')
    stub_request(:get, 'https://m/01/slide-01.jpg?v=1').to_return(body: 'jpg')
    with_modified_env(RAMON_DRIVE_POSTS_ID: 'raiz') { described_class.perform_now(peca.id) }
    expect(Ramon::DriveClient).to have_received(:ensure_folder).with('Carrossel', 'raiz')
    expect(Ramon::DriveClient).to have_received(:upload).with(hash_including(name: 'slide-01.jpg', parent_id: 'pasta1'))
    expect(Ramon::DriveClient).to have_received(:upload).with(hash_including(name: 'legenda.txt'))
    expect(peca.reload.drive_pasta_id).to eq 'pasta1'
  end
end
