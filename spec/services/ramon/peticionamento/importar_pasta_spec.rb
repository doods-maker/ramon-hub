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

  it 'PDF sem texto: marcador do LLM fora da lista fechada não recusa' do
    stub_download('a', pdf_sem_texto)
    stub_ler('marcadores' => ['[sic]', '[...]'])
    importar
    expect(peticao.leitura).to include('recusas' => [], 'estado' => 'lida')
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

  it 'releitura sem número nem CPF lidos: o que a petição tinha fica, marcado como incerto' do
    contato = create(:contact, account: account, cpf: '52998224725')
    importar
    peticao.update!(contact: contato)
    voltar_a_lendo
    stub_ler('numero_processo' => nil, 'tribunal' => nil)
    importar
    expect(peticao.reload).to have_attributes(numero_processo: numero_valido_trf4, contact: contato)
    expect(peticao.leitura['incertos']).to include('numero_processo', 'cpf')
  end

  it 'leitura que traz número e cliente não marca incerto' do
    contato = create(:contact, account: account, cpf: '52998224725')
    stub_ler('cpf' => contato.cpf)
    importar
    expect(peticao.reload.contact).to eq(contato)
    expect(peticao.leitura['incertos']).to eq([])
  end

  it 'inicial limpa o número sem marcar incerto' do
    importar
    voltar_a_lendo
    stub_ler('tipo' => 'inicial', 'numero_processo' => nil)
    importar
    expect(peticao.reload.numero_processo).to be_nil
    expect(peticao.leitura['incertos']).not_to include('numero_processo')
  end

  it 'não parece petição: responsável incerto' do
    stub_ler('e_peticao' => false)
    importar
    expect(peticao.leitura['incertos']).to include('responsavel')
  end

  it 'não parece petição na releitura: número antigo fica marcado como incerto' do
    importar
    voltar_a_lendo
    stub_ler('e_peticao' => false)
    importar
    expect(peticao.reload.numero_processo).to eq(numero_valido_trf4)
    expect(peticao.leitura['incertos']).to include('numero_processo', 'responsavel')
  end

  it 'arquivo acima de 30 MB é recusado sem baixar nem chamar o LLM' do
    stub_pasta([item('01 Petição.pdf', pdf, 'a').merge(size: 31.megabytes), item('02 Laudo.pdf', pdf, 'b').merge(size: 1.megabyte)])
    importar
    expect(Ramon::DriveClient).not_to have_received(:download)
    expect(Ramon::Peticionamento::LerPeca).not_to have_received(:call)
    expect(peticao.leitura['recusas']).to eq(['muito_grande:01 Petição.pdf'])
  end

  it 'pasta acima de 100 MB é recusada, mesmo com cada arquivo dentro do teto' do
    stub_pasta((1..4).map { |n| item("0#{n} P.pdf", pdf, n.to_s).merge(size: 26.megabytes) })
    importar
    expect(Ramon::DriveClient).not_to have_received(:download)
    expect(peticao.leitura['recusas']).to eq(['pasta_grande'])
  end

  it 'tamanho desconhecido conta como 0' do
    stub_pasta([item('01 Petição.pdf', pdf, 'a').merge(size: nil)])
    importar
    expect(peticao.leitura['recusas']).to eq([])
    expect(peticao.arquivos.count).to eq(1)
  end

  it 'arquivo que diz ser PDF e não é vira recusa nomeada, sem erro para o job repetir nem LLM' do
    stub_download('b', 'isto não é um PDF')
    importar
    expect(peticao.reload.leitura).to include('estado' => 'lida', 'recusas' => ['formato:02 Procuração.pdf'])
    expect(peticao.arquivos.count).to eq(0)
    expect(Ramon::Peticionamento::LerPeca).not_to have_received(:call)
  end

  it 'Drive sem `size`: o tamanho de verdade é conferido depois de baixar e vira recusa nomeada' do
    stub_pasta([item('01 Petição.pdf', pdf, 'a').merge(size: nil)])
    stub_const('Ramon::Peticionamento::AdicionarArquivo::MAX_ARQUIVO', 100)
    importar
    expect(peticao.reload.leitura).to include('estado' => 'lida', 'recusas' => ['muito_grande:01 Petição.pdf'])
    expect(peticao.arquivos.count).to eq(0)
  end

  it 'Drive sem `size`: pacote que passa do teto pelos bytes de verdade vira `pasta_grande`' do
    stub_pasta([item('01 Petição.pdf', pdf, 'a').merge(size: nil), item('02 Procuração.pdf', pdf, 'b').merge(size: nil)])
    stub_const('Ramon::Peticionamento::AdicionarArquivo::MAX_PASTA', 1_000)
    importar
    expect(peticao.reload.leitura['recusas']).to eq(['pasta_grande'])
    expect(peticao.arquivos.count).to eq(0)
  end

  it 'erro do Drive sobe, para o job tentar de novo' do
    allow(Ramon::DriveClient).to receive(:download).and_raise(Google::Apis::ServerError, 'x')
    expect { importar }.to raise_error(Google::Apis::ServerError)
  end
end
