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

  it 'recusa HEIC e petição protocolada' do
    expect { described_class.call(peticao, bytes: 'x', nome: 'a.heic', content_type: 'image/heic', origem: 'upload') }
      .to raise_error(ArgumentError, 'formato')
    peticao.update_columns(status: 'protocolada') # rubocop:disable Rails/SkipsModelValidations
    expect { described_class.call(peticao, bytes: 'x', nome: 'a.pdf', content_type: 'application/pdf', origem: 'upload') }
      .to raise_error(ArgumentError, 'protocolada')
  end
end
