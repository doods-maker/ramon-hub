require 'rails_helper'
require 'prawn'

RSpec.describe Ramon::Peticionamento::ImportarPasta do
  let(:account) { create(:account) }
  let(:criador) { create(:user, account: account, role: :administrator) }
  let(:time) { create(:team, account: account, name: Ramon::Papeis::JURIDICO) }
  let!(:brenda) { create(:user, name: 'Brenda Antunes', account: account).tap { |u| create(:team_member, team: time, user: u) } }
  let(:peticao) do
    account.peticoes.create!(criado_por: criador, responsavel: criador, status: 'conferencia', pela_pasta: true,
                             drive_pasta_id: 'pasta', prazo: Date.new(2026, 12, 1), leitura: { 'estado' => 'lendo' })
  end
  let(:pdf) { 'application/pdf' }
  let(:docx) { 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }

  def numero_valido_trf4
    dd = format('%02d', 98 - ('50012342026404720700'.to_i % 97))
    "5001234-#{dd}.2026.4.04.7207"
  end

  def item(nome, mime = pdf, id = 'x') = { id: id, name: nome, mime_type: mime, pasta: false }

  def pdf_com(texto) = Prawn::Document.new { text texto }.render
  def pdf_sem_texto = Prawn::Document.new { rectangle [0, 100], 50, 50 }.render

  def stub_pasta(itens) = allow(Ramon::DriveClient).to receive(:conteudo_da_pasta).with('pasta').and_return(itens)
  def stub_download(id, bytes) = allow(Ramon::DriveClient).to receive(:download).with(id).and_return([bytes, pdf, 'x.pdf'])

  def lida(**extra)
    { 'falhou' => false, 'e_peticao' => true, 'tipo' => 'intermediaria', 'numero_processo' => numero_valido_trf4, 'tribunal' => 'trf4',
      'cpf' => nil, 'nome_cliente' => nil, 'assinantes' => [{ 'nome' => 'Brenda Antunes', 'oab' => 'SC 1' }], 'titulo' => 'Réplica',
      'inicial' => {}, 'marcadores' => [], 'incertos' => [] }.merge(extra)
  end

  def stub_ler(**extra) = allow(Ramon::Peticionamento::LerPeca).to receive(:call).and_return(lida(**extra))

  def importar = described_class.call(peticao)

  # O endpoint de reler grava `lendo` antes de enfileirar.
  def voltar_a_lendo = peticao.update!(leitura: peticao.leitura.merge('estado' => 'lendo'))

  before do
    allow(Ramon::DriveClient).to receive(:download)
    allow(Ramon::DriveClient).to receive(:nomes_acima).and_return(['Fulano 123.456.789-09', 'Clientes'])
    stub_pasta([item('01 Petição.pdf', pdf, 'a'), item('02 Procuração.pdf', pdf, 'b')])
    stub_download('a', pdf_com('Texto da petição'))
    stub_download('b', pdf_com('Procuração'))
    stub_ler
  end

  it 'monta o pacote, com o primeiro como principal e o drive_file_id da origem' do
    importar
    expect(peticao.arquivos.pluck(:nome, :principal, :drive_file_id, :drive_origem_id))
      .to eq([['Petição.pdf', true, 'a', 'a'], ['Procuração.pdf', false, 'b', 'b']])
    expect(peticao.reload).to have_attributes(numero_processo: numero_valido_trf4, tribunal: 'trf4', responsavel: brenda, descricao: 'Réplica',
                                              inicial: false, prazo: Date.new(2026, 12, 1))
    expect(peticao.arquivos.first.tipo).to eq('peticao')
    expect(peticao.leitura).to include('estado' => 'lida', 'recusas' => [], 'avisos' => [], 'cpf_pasta' => '12345678909')
  end

  it 'recusa de regra não baixa nada nem chama o LLM' do
    stub_pasta([item('01 P.docx', docx)])
    importar
    expect(Ramon::DriveClient).not_to have_received(:download)
    expect(Ramon::Peticionamento::LerPeca).not_to have_received(:call)
    expect(peticao.leitura).to include('estado' => 'lida')
    expect(peticao.leitura['recusas']).to include('sem_pdf')
  end

  it 'avisos das regras (subpastas) vão para a leitura' do
    stub_pasta([item('01 Petição.pdf', pdf, 'a'), { id: 's', name: 'Outros', mime_type: 'x', pasta: true }])
    importar
    expect(peticao.leitura['avisos']).to eq(['subpastas:Outros'])
  end

  it 'marcador no texto da principal vira recusa' do
    stub_download('a', pdf_com('[CONFERIR] tese'))
    importar
    expect(peticao.leitura['recusas']).to eq(['marcador:[CONFERIR]'])
  end

  it 'PDF sem texto: usa os marcadores do LLM e avisa' do
    stub_download('a', pdf_sem_texto)
    stub_ler('marcadores' => ['[CAMPO'])
    importar
    expect(peticao.leitura).to include('recusas' => ['marcador:[CAMPO'])
    expect(peticao.leitura['avisos']).to include('sem_texto')
  end

  it 'PDF sem texto e LLM fora: os dois avisos' do
    stub_download('a', pdf_sem_texto)
    stub_ler('falhou' => true)
    importar
    expect(peticao.leitura['avisos']).to include('sem_texto', 'leitura_falhou')
  end

  it 'reler substitui o pacote em vez de acumular' do
    importar
    voltar_a_lendo
    importar
    expect(peticao.arquivos.count).to eq(2)
  end

  it 'petição que não está lendo (lida ou fora da conferência) não é tocada' do
    importar
    antes = peticao.arquivos.pluck(:id)
    importar # estado já é lida
    peticao.update_columns(status: 'rascunho', leitura: peticao.leitura.merge('estado' => 'lendo')) # rubocop:disable Rails/SkipsModelValidations
    importar
    expect(peticao.arquivos.pluck(:id)).to eq(antes)
  end

  it 'falha no download deixa o pacote antigo inteiro' do
    importar
    antes = peticao.arquivos.pluck(:id)
    voltar_a_lendo
    allow(Ramon::DriveClient).to receive(:download).with('b').and_raise(Google::Apis::ServerError, 'x')
    expect { importar }.to raise_error(Google::Apis::ServerError)
    expect(peticao.arquivos.pluck(:id)).to eq(antes)
  end

  it 'recusa, corrige a pasta e relê: responsável e descrição vêm da peça' do
    stub_pasta([item('01 P.docx', docx)])
    importar
    expect(peticao.leitura['recusas']).to include('sem_pdf')
    voltar_a_lendo
    stub_pasta([item('01 Petição.pdf', pdf, 'a')])
    importar
    expect(peticao.reload).to have_attributes(responsavel: brenda, descricao: 'Réplica')
  end

  it 'releitura: número e cliente da peça valem, responsável e descrição editados ficam' do
    importar
    peticao.update!(descricao: 'Editada', responsavel: criador)
    voltar_a_lendo
    importar
    expect(peticao.reload).to have_attributes(descricao: 'Editada', responsavel: criador, numero_processo: numero_valido_trf4)
  end

  it 'falha do LLM não trava: abre a conferência com aviso' do
    stub_ler('falhou' => true)
    importar
    expect(peticao.leitura).to include('estado' => 'lida')
    expect(peticao.leitura['avisos']).to include('leitura_falhou')
  end

  it 'peça que não parece petição: sem principal e com aviso' do
    stub_ler('e_peticao' => false)
    importar
    expect(peticao.arquivos.where(principal: true)).to be_empty
    expect(peticao.leitura['avisos']).to include('nao_parece_peticao')
  end

  it 'sem usuário para o responsável: avisa e mantém o atual' do
    stub_ler('assinantes' => [{ 'nome' => 'Ana Souza', 'oab' => 'SC 9' }])
    importar
    expect(peticao.reload.responsavel).to eq(criador)
    expect(peticao.leitura['avisos']).to include('responsavel_sem_usuario')
  end

  it 'inicial: marca e limpa o número' do
    stub_ler('tipo' => 'inicial')
    importar
    expect(peticao.reload).to have_attributes(inicial: true, numero_processo: nil)
  end

  it 'erro do Drive sobe, para o job tentar de novo' do
    allow(Ramon::DriveClient).to receive(:download).and_raise(Google::Apis::ServerError, 'x')
    expect { importar }.to raise_error(Google::Apis::ServerError)
  end
end
