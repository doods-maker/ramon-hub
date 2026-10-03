require 'rails_helper'

RSpec.describe Ramon::AgendaHojeService do
  let(:account) { create(:account) }
  let!(:brenda) { create(:user, account: account, email: 'brendantunes_@hotmail.com') }

  # Segunda, 10h em SP — dentro do expediente (Ramon::AdvboxCache).
  around { |example| travel_to(Time.zone.parse('2026-10-05 13:00:00 UTC')) { example.run } }

  before do
    allow(Ramon::AdvboxClient).to receive(:posts).and_return(
      'data' => [
        { 'id' => 1, 'task' => 'ATENDIMENTO', 'notes' => 'traz CNIS', 'date' => '2026-10-05 14:00:00',
          'lawsuit' => { 'customers' => [{ 'customer_id' => 9, 'name' => 'INSS', 'customers_origins_id' => 25_705 },
                                         { 'customer_id' => 7, 'name' => 'MARIA SILVA', 'customers_origins_id' => nil }] },
          'users' => [{ 'user_id' => 260_009, 'name' => 'BRENDA ANTUNES' }] },
        { 'id' => 2, 'task' => 'ANALISAR SENTENÇA', 'date' => '2026-10-05 00:00:00', 'lawsuit' => { 'customers' => [] }, 'users' => [] },
        { 'id' => 3, 'task' => 'ATENDIMENTO', 'date' => '2026-10-07 09:00:00', 'lawsuit' => { 'customers' => [] }, 'users' => [] }
      ]
    )
    allow(Ramon::AdvboxClient).to receive(:settings)
      .and_return('users' => [{ 'id' => 260_009, 'email' => 'BRENDANTUNES_@HOTMAIL.COM' }])
  end

  it 'lista só ATENDIMENTO de hoje, pula a parte contrária e casa o responsável por e-mail' do
    linhas = described_class.new(account).perform

    expect(linhas.size).to eq(1)
    expect(linhas.first).to include(advbox_post_id: 1, cliente_nome: 'MARIA SILVA', advbox_customer_id: 7, hora: '14:00',
                                    notas: 'traz CNIS', responsavel_advbox: 'BRENDA ANTUNES', destinatario_id: brenda.id)
  end

  it 'sai da mesma busca da semana (sem chamada própria)' do
    described_class.new(account).perform
    expect(Ramon::AdvboxClient).to have_received(:posts).once
    expect(Ramon::AdvboxClient).to have_received(:posts).with(hash_including(date_start: '2026-10-05', date_end: '2026-10-11'))
  end
end
