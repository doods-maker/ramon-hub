require 'rails_helper'

RSpec.describe Ramon::AgendaHojeService do
  let(:account) { create(:account) }
  let!(:brenda) { create(:user, account: account, email: 'brendantunes_@hotmail.com') }

  before do
    allow(Ramon::AdvboxClient).to receive(:posts).and_return(
      'data' => [
        { 'id' => 1, 'task' => 'ATENDIMENTO', 'notes' => 'traz CNIS',
          'lawsuit' => { 'customers' => [{ 'customer_id' => 9, 'name' => 'INSS', 'customers_origins_id' => 25_705 },
                                         { 'customer_id' => 7, 'name' => 'MARIA SILVA', 'customers_origins_id' => nil }] },
          'users' => [{ 'user_id' => 260_009, 'name' => 'BRENDA ANTUNES' }] },
        { 'id' => 2, 'task' => 'ANALISAR SENTENÇA', 'lawsuit' => { 'customers' => [] }, 'users' => [] }
      ]
    )
    allow(Ramon::AdvboxClient).to receive(:settings)
      .and_return('users' => [{ 'id' => 260_009, 'email' => 'BRENDANTUNES_@HOTMAIL.COM' }])
  end

  it 'lista só ATENDIMENTO, pula a parte contrária e casa o responsável por e-mail' do
    linhas = described_class.new(account).perform

    expect(linhas.size).to eq(1)
    expect(linhas.first).to include(advbox_post_id: 1, cliente_nome: 'MARIA SILVA', advbox_customer_id: 7,
                                    notas: 'traz CNIS', responsavel_advbox: 'BRENDA ANTUNES', destinatario_id: brenda.id)
  end

  it 'pede as tarefas do dia de São Paulo' do
    travel_to(Time.zone.parse('2026-10-03 01:00:00 UTC')) { described_class.new(account).perform }
    expect(Ramon::AdvboxClient).to have_received(:posts).with(hash_including(date_start: '2026-10-02', date_end: '2026-10-02'))
  end
end
