require 'rails_helper'
require 'prawn'

RSpec.describe Ramon::Peticionamento::MarcadoresRascunho do
  let(:lista) do
    ['[CAMPO', '[CONFERIR]', '[NB]', '[DIB]', '[CPF]', '[VALOR]', '[DATA]', '[OAB]', '[NOME DA PARTE]', '[ADVOGADO(A) ASSOCIADO(A)]',
     '[RG]', '[ENDEREÇO]', '[DATA DE NASCIMENTO]', '[EMPREGADOR]', '[CIDADE]', '[DCB]', '[CID]', '[DER]', '[NOME DE TERCEIRO]',
     '[VARA', '[RITO ORDINÁRIO', '[RITO JEF', '[NATUREZA]', '[DATA DO ACIDENTE]', '[DATA DE INÍCIO]', '[ESCOLHER', '[TRANSCREVER',
     'CONTROLE INTERNO', 'RASCUNHO', 'Notas ao advogado', 'Conferência humana', 'O que esta minuta NÃO faz']
  end

  it 'tem exatamente a lista da spec' do
    expect(described_class::LISTA).to match_array(lista)
  end

  it 'acha marcador mesmo com espaços quebrados, e não recusa [...] nem [sic]' do
    expect(described_class.no_texto("valor [CAMPO: a apurar]\nCONTROLE   INTERNO")).to contain_exactly('[CAMPO', 'CONTROLE INTERNO')
    expect(described_class.no_texto('parte [EMPREGADOR] e [SIC]')).to eq(['[EMPREGADOR]'])
    expect(described_class.no_texto('conforme [...] e [sic], órgão de controle interno')).to eq([])
  end

  it 'lê o texto de um PDF real e devolve vazio em lixo' do
    pdf = Prawn::Document.new.tap { |d| d.text 'Conferência humana' }.render
    expect(described_class.no_texto(described_class.texto_do_pdf(pdf))).to eq(['Conferência humana'])
    expect(described_class.texto_do_pdf('lixo')).to eq('')
  end
end
