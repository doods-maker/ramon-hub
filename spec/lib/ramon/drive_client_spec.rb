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

  it 'children recusa id que não é id (fecharia a aspa da query) sem chamar o Drive' do
    allow(api).to receive(:list_files)
    expect { described_class.children("x' in parents or name contains '") }.to raise_error(ArgumentError)
    expect(api).not_to have_received(:list_files)
  end

  it 'search escapa barra e aspas' do
    allow(api).to receive(:list_files).and_return(Google::Apis::DriveV3::FileList.new(files: []))
    described_class.search("a\\b'c")
    expect(api).to have_received(:list_files).with(hash_including(q: a_string_including("name contains 'a\\\\b\\'c'")))
  end

  it 'marcadores_de_pasta_pronta segue as páginas até o fim e traz pai e tamanho' do
    pagina1 = Google::Apis::DriveV3::FileList.new(files: [Google::Apis::DriveV3::File.new(id: 'm1', parents: ['p1'], size: 20)],
                                                  next_page_token: 'tok')
    pagina2 = Google::Apis::DriveV3::FileList.new(files: [Google::Apis::DriveV3::File.new(id: 'm2', parents: ['p2'], size: 30)])
    allow(api).to receive(:list_files).and_return(pagina1, pagina2)
    expect(described_class.marcadores_de_pasta_pronta).to eq([{ id: 'm1', parents: ['p1'], size: 20 }, { id: 'm2', parents: ['p2'], size: 30 }])
    expect(api).to have_received(:list_files).with(hash_including(page_token: 'tok'))
    expect(api).to have_received(:list_files).with(hash_including(q: a_string_including("name = '_pasta-pronta.json'"))).twice
  end

  it 'conteudo_da_pasta segue as páginas até o fim, sem filtro de tipos' do
    pagina1 = Google::Apis::DriveV3::FileList.new(files: [fake('1', 'b.pdf', 'application/pdf')], next_page_token: 'tok')
    pagina2 = Google::Apis::DriveV3::FileList.new(files: [fake('2', 'a.docx', 'application/msword')])
    allow(api).to receive(:list_files).and_return(pagina1, pagina2)
    expect(described_class.conteudo_da_pasta('p').pluck(:id, :size)).to eq([['2', 10], ['1', 10]])
    expect(api).to have_received(:list_files).with(hash_including(page_token: 'tok', q: "'p' in parents and trashed = false",
                                                                  fields: a_string_including('nextPageToken', 'size')))
  end

  it 'aposentar_marcador renomeia, porque lixeira exige ser dono do arquivo' do
    allow(api).to receive(:update_file)
    described_class.aposentar_marcador('m1')
    expect(api).to have_received(:update_file).with('m1', { name: '_pasta-pronta.usada.json' }, hash_including(supports_all_drives: true))
  end

  describe 'dentro_da_raiz?' do
    before { allow(described_class).to receive(:root_id).and_return('raiz') }

    it 'sobe os pais até achar a raiz' do
      allow(described_class).to receive(:parent_of).with('p1').and_return('a')
      allow(described_class).to receive(:parent_of).with('a').and_return('raiz')
      expect(described_class.dentro_da_raiz?('p1')).to be(true)
    end

    it 'false quando a cadeia termina sem passar pela raiz' do
      allow(described_class).to receive(:parent_of).with('p1').and_return(nil)
      expect(described_class.dentro_da_raiz?('p1')).to be(false)
    end

    it 'false além de 10 níveis' do
      allow(described_class).to receive(:parent_of) { |id| "#{id}x" }
      expect(described_class.dentro_da_raiz?('p')).to be(false)
    end
  end

  describe '.lixeira' do
    before do
      allow(described_class).to receive(:root_id).and_return('raiz')
      allow(api).to receive(:update_file)
    end

    it 'manda à lixeira a pasta dentro da raiz' do
      allow(described_class).to receive(:parent_of).with('cliente').and_return('raiz')
      described_class.lixeira('cliente')
      expect(api).to have_received(:update_file).with('cliente', { trashed: true }, hash_including(supports_all_drives: true))
    end

    it 'recusa a raiz e o que está fora dela, sem tocar no Drive', :aggregate_failures do
      allow(described_class).to receive(:parent_of).with('fora').and_return(nil)
      expect { described_class.lixeira('raiz') }.to raise_error(ArgumentError)
      expect { described_class.lixeira('fora') }.to raise_error(ArgumentError)
      expect(api).not_to have_received(:update_file)
    end
  end

  describe '.search_na_raiz' do
    before { allow(described_class).to receive(:root_id).and_return('raiz') }

    it 'deixa só o que está dentro da raiz; pergunta cada pasta ao Drive uma vez', :aggregate_failures do
      allow(described_class).to receive(:search).with('laudo').and_return(
        [{ id: 'a', parents: ['sub'] }, { id: 'b', parents: ['sub'] }, { id: 'c', parents: ['fora'] }, { id: 'd', parents: nil }]
      )
      allow(described_class).to receive(:parent_of).with('sub').and_return('raiz')
      allow(described_class).to receive(:parent_of).with('fora').and_return(nil)

      expect(described_class.search_na_raiz('laudo').pluck(:id)).to eq(%w[a b])
      expect(described_class).to have_received(:parent_of).with('sub').once
    end
  end

  it 'search com menos de 3 letras não chama a API' do
    expect(api).not_to receive(:list_files)
    expect(described_class.search('ab')).to eq([])
  end

  describe '.substituir' do
    let(:nome) { 'Memória de cálculo - Ana.xlsx' }
    let(:args) { { name: nome, io: StringIO.new('x'), content_type: 'application/pdf', parent_id: 'p1' } }

    it 'troca o conteúdo do arquivo de mesmo nome' do
      allow(described_class).to receive(:conteudo_da_pasta).with('p1').and_return([{ id: 'f9', name: nome, pasta: false }])
      expect(api).to receive(:update_file).with('f9', upload_source: anything, content_type: 'application/pdf', supports_all_drives: true)
      expect(described_class.substituir(**args)).to eq('f9')
    end

    it 'sobe novo quando não há arquivo com o nome' do
      allow(described_class).to receive(:conteudo_da_pasta).with('p1').and_return([{ id: 'x', name: 'outro', pasta: false }])
      expect(described_class).to receive(:upload).with(**args).and_return('n1')
      expect(described_class.substituir(**args)).to eq('n1')
    end

    it 'ignora pasta com o mesmo nome' do
      allow(described_class).to receive(:conteudo_da_pasta).with('p1').and_return([{ id: 'd1', name: nome, pasta: true }])
      expect(described_class).to receive(:upload).with(**args).and_return('n2')
      expect(described_class.substituir(**args)).to eq('n2')
    end
  end
end
