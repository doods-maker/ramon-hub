require 'rails_helper'

RSpec.describe Ramon::Peticionamento::AdicionarArquivo do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:peticao) { account.peticoes.create!(criado_por: user, responsavel: user, inicial: true, tribunal: 'tjsc') }
  let(:pdf) { File.binread(Rails.root.join('spec/assets/sample.pdf')) }

  it 'PDF entra com tipo sugerido e posição seguinte' do
    a = described_class.call(peticao, bytes: pdf, nome: 'Procuração.pdf', content_type: 'application/pdf', origem: 'upload')
    b = described_class.call(peticao, bytes: pdf, nome: 'Petição.pdf', content_type: 'application/pdf', origem: 'upload', principal: true)
    expect([a.reload.posicao, a.tipo, b.posicao, b.principal]).to eq([1, 'procuracao', 2, true])
    expect(a.file).to be_attached
  end

  it 'principal desmarca a anterior' do
    a = described_class.call(peticao, bytes: pdf, nome: 'A.pdf', content_type: 'application/pdf', origem: 'upload', principal: true)
    described_class.call(peticao, bytes: pdf, nome: 'B.pdf', content_type: 'application/pdf', origem: 'upload', principal: true)
    expect(a.reload.principal).to be(false)
  end

  it 'imagem vira PDF' do
    png = File.binread(Rails.root.join('spec/assets/sample.png'))
    a = described_class.call(peticao, bytes: png, nome: 'RG frente.png', content_type: 'image/png', origem: 'upload')
    expect([a.nome, a.file.content_type, a.tipo]).to eq(['RG frente.pdf', 'application/pdf', 'documento_identificacao'])
    expect(a.tamanho).to eq(a.file.blob.byte_size)
  end

  it 'recusa o que diz ser PDF ou imagem e não é: vale a assinatura dos primeiros bytes' do
    [['application/pdf', 'MZ executável'], ['image/png', pdf], ['image/jpeg', 'GIF89a']].each do |tipo, bytes|
      expect { described_class.call(peticao, bytes: bytes, nome: 'a.pdf', content_type: tipo, origem: 'upload') }
        .to raise_error(ArgumentError, 'formato')
    end
    expect(peticao.arquivos.count).to eq(0)
  end

  it 'recusa arquivo acima do teto e pacote que passaria do teto, os mesmos da leitura da pasta' do
    stub_const("#{described_class}::MAX_ARQUIVO", pdf.bytesize)
    stub_const("#{described_class}::MAX_PASTA", pdf.bytesize + 1)
    expect { described_class.call(peticao, bytes: "#{pdf} ", nome: 'a.pdf', content_type: 'application/pdf', origem: 'upload') }
      .to raise_error(ArgumentError, 'muito_grande')
    described_class.call(peticao, bytes: pdf, nome: 'a.pdf', content_type: 'application/pdf', origem: 'upload')
    expect { described_class.call(peticao, bytes: pdf, nome: 'b.pdf', content_type: 'application/pdf', origem: 'upload') }
      .to raise_error(ArgumentError, 'pasta_grande')
    expect(peticao.arquivos.count).to eq(1)
  end

  it 'os tetos são os da leitura da pasta' do
    expect([described_class::MAX_ARQUIVO, described_class::MAX_PASTA]).to eq([30.megabytes, 100.megabytes])
  end

  it 'recusa HEIC e petição protocolada' do
    expect { described_class.call(peticao, bytes: 'x', nome: 'a.heic', content_type: 'image/heic', origem: 'upload') }
      .to raise_error(ArgumentError, 'formato')
    peticao.update_columns(status: 'protocolada') # rubocop:disable Rails/SkipsModelValidations
    expect { described_class.call(peticao, bytes: 'x', nome: 'a.pdf', content_type: 'application/pdf', origem: 'upload') }
      .to raise_error(ArgumentError, 'protocolada')
  end
end
