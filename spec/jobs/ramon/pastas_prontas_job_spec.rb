require 'rails_helper'

RSpec.describe Ramon::PastasProntasJob do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:brenda) { create(:user, account: account, role: :agent) }
  let(:marcadores) { [] }
  let(:jsons) { {} }

  before do
    time = create(:team, account: account, name: Ramon::Papeis::JURIDICO)
    create(:team_member, team: time, user: brenda)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('RAMON_PETICOES_ACCOUNT_ID', 2).and_return(account.id)
    allow(Ramon::DriveClient).to receive_messages(configured?: true, dentro_da_raiz?: true, aposentar_marcador: nil)
    allow(Ramon::DriveClient).to receive(:marcadores_de_pasta_pronta) { marcadores }
    allow(Ramon::DriveClient).to receive(:download) { |id| [jsons.fetch(id), 'application/json', '_pasta-pronta.json'] }
  end

  def stub_marcador(id, pasta:, json:, size: 20)
    marcadores << { id: id, parents: [pasta], size: size }
    jsons[id] = json.is_a?(String) ? json : json.to_json
  end

  def sino(user) = user.notifications.where(notification_type: 'ramon_pasta_pronta')

  it 'marcador novo cria o item e avisa só o responsável, pelo sino' do
    stub_marcador('m1', pasta: 'p1', json: { responsavel_email: brenda.email, titulo: 'Réplica' })
    expect { described_class.perform_now }.to change(account.pastas_prontas, :count).by(1)
    pasta = account.pastas_prontas.sole
    expect(pasta).to have_attributes(drive_pasta_id: 'p1', titulo: 'Réplica', responsavel_id: brenda.id)
    expect(sino(brenda).sole).to have_attributes(primary_actor: pasta, meta: { 'label' => 'Réplica' })
    expect(Notification.where(notification_type: 'ramon_pasta_pronta').count).to eq(1)
    expect(Ramon::NtfyPushJob).not_to have_been_enqueued
  end

  it 'rodar de novo não duplica nem reavisa' do
    stub_marcador('m1', pasta: 'p1', json: { responsavel_email: brenda.email, titulo: 'Réplica' })
    2.times { described_class.perform_now }
    expect(account.pastas_prontas.count).to eq(1)
    expect(brenda.notifications.count).to eq(1)
  end

  it 'sem responsável (ou e-mail desconhecido): item sem dono, e avisa os admins' do
    stub_marcador('m1', pasta: 'p1', json: { responsavel_email: '', titulo: 'A' })
    stub_marcador('m2', pasta: 'p2', json: { responsavel_email: 'ninguem@exemplo.com', titulo: 'B' })
    described_class.perform_now
    expect(account.pastas_prontas.pluck(:drive_pasta_id, :responsavel_id)).to contain_exactly(['p1', nil], ['p2', nil])
    expect(sino(admin).count).to eq(2)
    expect(sino(brenda).count).to eq(0)
  end

  it 'JSON sem chaves: usa título vazio e cria sem dono, sem derrubar' do
    stub_marcador('m1', pasta: 'p1', json: {})
    described_class.perform_now
    expect(account.pastas_prontas.sole).to have_attributes(titulo: nil, responsavel_id: nil)
    expect(sino(admin).sole.meta['label']).to eq(I18n.t('notifications.pasta_sem_titulo'))
  end

  it 'pasta já virou petição: não cria item' do
    account.peticoes.create!(criado_por: brenda, responsavel: brenda, status: 'conferencia', pela_pasta: true, drive_pasta_id: 'p1')
    stub_marcador('m1', pasta: 'p1', json: { titulo: 'A' })
    expect { described_class.perform_now }.not_to change(PastaPronta, :count)
    expect(Notification.where(notification_type: 'ramon_pasta_pronta').count).to eq(0)
  end

  it 'petição passa a existir: o item sai com o sino e o marcador é aposentado; marcador sumiu: o item sai' do
    stub_marcador('m1', pasta: 'p1', json: { responsavel_email: brenda.email })
    stub_marcador('m2', pasta: 'p2', json: { responsavel_email: brenda.email })
    stub_marcador('m3', pasta: 'p3', json: { responsavel_email: brenda.email })
    described_class.perform_now
    account.peticoes.create!(criado_por: brenda, responsavel: brenda, status: 'conferencia', pela_pasta: true, drive_pasta_id: 'p1')
    marcadores.delete_at(1)
    described_class.perform_now
    expect(account.pastas_prontas.pluck(:drive_pasta_id)).to eq(['p3'])
    expect(brenda.notifications.count).to eq(1)
    expect(Ramon::DriveClient).to have_received(:aposentar_marcador).once.with('m1')
  end

  it 'lista vazia não apaga os itens, mas petição existente ainda tira o dela' do
    stub_marcador('m1', pasta: 'p1', json: { titulo: 'A' })
    stub_marcador('m2', pasta: 'p2', json: { titulo: 'B' })
    described_class.perform_now
    account.peticoes.create!(criado_por: brenda, responsavel: brenda, status: 'conferencia', pela_pasta: true, drive_pasta_id: 'p1')
    marcadores.clear
    described_class.perform_now
    expect(account.pastas_prontas.pluck(:drive_pasta_id)).to eq(['p2'])
  end

  it 'falha ao aposentar o marcador só registra log e o lote segue' do
    account.peticoes.create!(criado_por: brenda, responsavel: brenda, status: 'conferencia', pela_pasta: true, drive_pasta_id: 'p1')
    stub_marcador('m1', pasta: 'p1', json: { titulo: 'A' })
    stub_marcador('m2', pasta: 'p2', json: { titulo: 'B' })
    allow(Ramon::DriveClient).to receive(:aposentar_marcador).and_raise(Google::Apis::ServerError.new('fora'))
    allow(Rails.logger).to receive(:warn)
    expect { described_class.perform_now }.not_to raise_error
    expect(account.pastas_prontas.pluck(:drive_pasta_id)).to eq(['p2'])
    expect(Rails.logger).to have_received(:warn).with(/aposentar marcador falhou.*marcador=m1/)
  end

  it 'marcador acima de 64 KB é ignorado com log, sem baixar' do
    stub_marcador('m1', pasta: 'p1', json: { titulo: 'A' }, size: 64.kilobytes + 1)
    allow(Rails.logger).to receive(:warn)
    expect { described_class.perform_now }.not_to change(PastaPronta, :count)
    expect(Ramon::DriveClient).not_to have_received(:download)
    expect(Rails.logger).to have_received(:warn).with(/grande demais\) marcador=m1/)
  end

  it 'título enorme é cortado em 200 caracteres' do
    stub_marcador('m1', pasta: 'p1', json: { titulo: 'x' * 500 })
    described_class.perform_now
    expect(account.pastas_prontas.sole.titulo.length).to eq(200)
  end

  it 'pasta fora da raiz do escritório é ignorada com log' do
    allow(Ramon::DriveClient).to receive(:dentro_da_raiz?).with('p1').and_return(false)
    stub_marcador('m1', pasta: 'p1', json: { titulo: 'A' })
    stub_marcador('m2', pasta: 'p2', json: { titulo: 'B' })
    allow(Rails.logger).to receive(:warn)
    described_class.perform_now
    expect(account.pastas_prontas.pluck(:drive_pasta_id)).to eq(['p2'])
    expect(Rails.logger).to have_received(:warn).with(/fora da raiz\) marcador=m1/)
  end

  it 'responsável que não é admin nem do time advogados conta como sem dono' do
    fora = create(:user, account: account, role: :agent)
    stub_marcador('m1', pasta: 'p1', json: { responsavel_email: fora.email, titulo: 'A' })
    described_class.perform_now
    expect(account.pastas_prontas.sole.responsavel_id).to be_nil
    expect(sino(admin).count).to eq(1)
    expect(sino(fora).count).to eq(0)
  end

  it 'JSON quebrado no marcador é ignorado com log, sem derrubar os demais nem apagar o item existente' do
    stub_marcador('m0', pasta: 'p0', json: { titulo: 'Velha' })
    described_class.perform_now
    stub_marcador('m1', pasta: 'p1', json: '{quebrado')
    stub_marcador('m2', pasta: 'p2', json: { titulo: 'Boa' })
    allow(Rails.logger).to receive(:warn)
    described_class.perform_now
    expect(account.pastas_prontas.pluck(:drive_pasta_id)).to contain_exactly('p0', 'p2')
    expect(Rails.logger).to have_received(:warn).with(/JSON inválido marcador=m1/)
  end

  it 'falha na listagem do Drive não apaga os itens' do
    stub_marcador('m1', pasta: 'p1', json: { titulo: 'A' })
    described_class.perform_now
    allow(Ramon::DriveClient).to receive(:marcadores_de_pasta_pronta).and_raise(Google::Apis::ServerError.new('fora'))
    expect { described_class.perform_now }.to raise_error(Google::Apis::ServerError)
    expect(account.pastas_prontas.count).to eq(1)
  end

  it 'Drive desligado: não faz nada' do
    allow(Ramon::DriveClient).to receive(:configured?).and_return(false)
    described_class.perform_now
    expect(Ramon::DriveClient).not_to have_received(:marcadores_de_pasta_pronta)
  end
end
