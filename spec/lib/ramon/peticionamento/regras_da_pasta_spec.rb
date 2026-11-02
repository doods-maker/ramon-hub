require 'rails_helper'

RSpec.describe Ramon::Peticionamento::RegrasDaPasta do
  let(:pdf) { 'application/pdf' }
  let(:docx) { 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }

  def item(name, mime = 'application/pdf', pasta: false) = { id: name, name: name, mime_type: mime, pasta: pasta }

  it 'ordena pelo número, inclusive NN.N, e limpa o nome' do
    r = described_class.call([item('10 Laudo.pdf'), item('02.1-RG.pdf'), item('01 Petição.pdf'), item('02.2-CPF.pdf')])
    expect(r.arquivos.pluck(:name)).to eq(['01 Petição.pdf', '02.1-RG.pdf', '02.2-CPF.pdf', '10 Laudo.pdf'])
    expect(r.arquivos.pluck(:nome_limpo)).to eq(['Petição.pdf', 'RG.pdf', 'CPF.pdf', 'Laudo.pdf'])
    expect(r.recusas).to eq([])
  end

  it 'Word com PDF de mesmo número é ignorado' do
    r = described_class.call([item('01 Petição.docx', docx), item('01 Petição.pdf')])
    expect(r.arquivos.pluck(:name)).to eq(['01 Petição.pdf'])
    expect(r.recusas).to eq([])
  end

  it 'recusa: só Word, sem PDF, sem número, número repetido e formato estranho' do
    expect(described_class.call([item('01 Petição.docx', docx)]).recusas).to eq(['sem_pdf', 'word_sem_pdf:01 Petição.docx'])
    expect(described_class.call([]).recusas).to eq(['sem_pdf'])
    expect(described_class.call([item('01 P.pdf'), item('Laudo.pdf')]).recusas).to eq(['sem_numero:Laudo.pdf'])
    expect(described_class.call([item('01 P.pdf'), item('01 Q.pdf')]).recusas).to eq(['numero_repetido:01 Q.pdf'])
    expect(described_class.call([item('01 P.pdf'), item('02 x.zip', 'application/zip')]).recusas).to eq(['formato:02 x.zip'])
  end

  it 'imagem entra; subpasta vira aviso; arquivo com _ é ignorado' do
    r = described_class.call([item('01 P.pdf'), item('02 RG.jpg', 'image/jpeg'), item('Extras', 'folder', pasta: true),
                              item('_pasta-pronta.json', 'application/json')])
    expect(r.arquivos.size).to eq(2)
    expect(r.avisos).to eq(['subpastas:Extras'])
    expect(r.recusas).to eq([])
  end

  it 'recusa quando a peça principal é imagem' do
    expect(described_class.call([item('01 RG.jpg', 'image/jpeg'), item('02 P.pdf')]).recusas).to eq(['sem_pdf'])
  end
end
