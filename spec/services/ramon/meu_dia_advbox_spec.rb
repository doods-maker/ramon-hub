require 'rails_helper'

RSpec.describe Ramon::MeuDiaAdvbox do
  let(:account) { create(:account) }
  let(:brenda) { create(:user, account: account, email: 'brenda@example.com') }
  let(:eu) { { 'user_id' => 260_009, 'name' => 'BRENDA ANTUNES', 'completed' => nil } }
  let(:cliente) { { 'customer_id' => 7, 'name' => 'MARIA SILVA', 'customers_origins_id' => 596_175 } }
  let(:inss) { { 'customer_id' => 9, 'name' => 'INSS', 'customers_origins_id' => 25_705 } }

  let(:tarefas) do
    [
      tarefa(1, '2026-11-09', 'task' => 'AUDIÊNCIA', 'date_deadline' => '2026-11-12 00:00:00', 'local' => 'Fórum de Tubarão'),
      tarefa(2, '2026-11-09', 'users' => [eu.merge('completed' => '2026-11-09 11:00:00')]),
      tarefa(3, '2026-11-11'),
      tarefa(4, '2026-11-16'),
      tarefa(5, '2026-11-17'),
      tarefa(6, '2026-11-12', 'users' => [eu.merge('completed' => '2026-11-09 11:00:00')]),
      tarefa(7, '2026-11-09', 'users' => [{ 'user_id' => 1, 'name' => 'OUTRA', 'completed' => nil }]),
      tarefa(8, '2026-11-02', 'task' => 'SOLICITAR DOCUMENTOS',
                              'notes' => "SITUAÇÃO: Esteira concluída com rascunho da petição inicial. Depende de laudo.\n\n" \
                                         'RASCUNHOS: Clientes/Maria Silva/Esteira/Petição inicial — Maria Silva.docx (caminho impresso: x)'),
      tarefa(9, '2026-11-05', 'task' => 'AGUARDANDO DOCUMENTOS CLIENTE',
                              'notes' => "SITUAÇÃO (retomada de 05/11/2026): parou por falta de laudo\n\nRASCUNHOS: Clientes/Maria Silva/Esteira/ " \
                                         '(formato antigo: 03 CNIS.md) e Esteira/_interno/. Não há .docx de peça.'),
      tarefa(10, '2026-11-03', 'notes' => 'SITUAÇÃO: já revisada', 'users' => [eu.merge('completed' => '2026-11-04 09:00:00')]),
      tarefa(11, '2026-11-04', 'notes' => 'Ligar para o cliente sobre a SITUAÇÃO do processo'),
      tarefa(12, '2026-11-01', 'notes' => "SITUAÇÃO (retomada 01/11 às 10:30): art. 42 cumprido. Falta laudo.\n\n" \
                                          'RASCUNHOS: Esteira/. Não há .docx de peça.')
    ]
  end

  def tarefa(id, data, extra = {})
    { 'id' => id, 'date' => "#{data} 00:00:00", 'task' => 'PERÍCIA', 'created_at' => "#{data} 10:00:00",
      'lawsuit' => { 'customers' => [inss, cliente] }, 'users' => [eu] }.merge(extra)
  end

  before do
    allow(Ramon::AdvboxClient).to receive(:settings)
      .and_return('users' => [{ 'id' => 260_009, 'name' => 'BRENDA ANTUNES', 'email' => 'BRENDA@EXAMPLE.COM' }])
    allow(Ramon::AdvboxClient).to receive(:posts).and_return('totalCount' => tarefas.size, 'data' => tarefas)
  end

  def meu_dia(user = brenda)
    travel_to(Time.zone.parse('2026-11-09 15:00:00 UTC')) { described_class.new(account, user).perform }
  end

  it 'pede as tarefas da pessoa de 2 semanas atrás até 7 dias à frente, no dia de São Paulo' do
    travel_to(Time.zone.parse('2026-11-10 01:00:00 UTC')) { described_class.new(account, brenda).perform }

    expect(Ramon::AdvboxClient).to have_received(:posts)
      .with(hash_including(user_name: 'BRENDA ANTUNES', date_start: '2026-10-26', date_end: '2026-11-16'))
  end

  it 'hoje = as tarefas dela com data de hoje, concluídas marcadas, com cliente, prazo e local' do
    hoje = meu_dia[:hoje]

    expect(hoje.pluck(:advbox_post_id)).to eq([1, 2])
    expect(hoje.first).to include(tarefa: 'AUDIÊNCIA', cliente_nome: 'MARIA SILVA', data: '2026-11-09',
                                  prazo: '2026-11-12', local: 'Fórum de Tubarão', concluida: false)
    expect(hoje.second).to include(concluida: true)
  end

  it 'semana = só as abertas de amanhã até 7 dias à frente, em ordem de data' do
    expect(meu_dia[:semana].pluck(:advbox_post_id)).to eq([3, 4])
  end

  it 'esteira = tarefas abertas que abrem com SITUAÇÃO, a peça só quando o .docx está em Esteira/' do
    esteira = meu_dia[:esteira]

    expect(esteira.pluck(:advbox_post_id)).to eq([9, 8, 12])
    expect(esteira.second).to include(cliente_nome: 'MARIA SILVA',
                                      situacao: 'Esteira concluída com rascunho da petição inicial.',
                                      peca: 'Petição inicial — Maria Silva.docx')
    expect(esteira.first).to include(situacao: 'parou por falta de laudo', peca: nil)
    expect(esteira.third).to include(situacao: 'art. 42 cumprido.', peca: nil)
  end

  it 'busca a página seguinte quando o ADVBOX diz que há mais' do
    allow(Ramon::AdvboxClient).to receive(:posts).with(hash_including(offset: 0))
                                                 .and_return('totalCount' => 101, 'data' => [tarefa(1, '2026-11-09')] * 100)
    allow(Ramon::AdvboxClient).to receive(:posts).with(hash_including(offset: 100))
                                                 .and_return('totalCount' => 101, 'data' => [tarefa(3, '2026-11-11')])

    expect(meu_dia[:semana].pluck(:advbox_post_id)).to eq([3])
  end

  it 'sem usuário casado no ADVBOX, devolve vazio sem gastar chamada' do
    sem_advbox = create(:user, account: account, email: 'sem-advbox@example.com')

    expect(meu_dia(sem_advbox)).to eq(hoje: [], semana: [], esteira: [])
    expect(Ramon::AdvboxClient).not_to have_received(:posts)
  end

  it 'guarda a busca em cache por pessoa' do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    meu_dia
    meu_dia

    expect(Ramon::AdvboxClient).to have_received(:posts).once
  end
end
