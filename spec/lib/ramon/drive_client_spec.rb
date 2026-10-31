require 'rails_helper'

RSpec.describe Ramon::DriveClient do
  let(:api) { instance_double(Google::Apis::DriveV3::DriveService) }

  before { allow(described_class).to receive(:service).and_return(api) }

  def fake(id, name, mime) = Google::Apis::DriveV3::File.new(id: id, name: name, mime_type: mime, size: 10)

  it 'children filtra e ordena pastas primeiro' do
    allow(api).to receive(:list_files).and_return(
      Google::Apis::DriveV3::FileList.new(files: [fake('1', 'b.pdf', 'application/pdf'), fake('2', 'Zeta', described_class::FOLDER_MIME)])
    )
    r = described_class.children('root')
    expect(r.pluck(:id, :pasta)).to eq([['2', true], ['1', false]])
    expect(api).to have_received(:list_files).with(hash_including(page_size: 200, supports_all_drives: true))
  end

  it 'search com menos de 3 letras não chama a API' do
    expect(api).not_to receive(:list_files)
    expect(described_class.search('ab')).to eq([])
  end
end
