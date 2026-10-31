require 'rails_helper'

RSpec.describe ChatCanal do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:brenda) { create(:user, account: account, role: :agent) }
  let!(:gabriela) { create(:user, account: account, role: :agent) }
  let(:advogados) { create(:team, account: account, name: 'advogados') }

  before { create(:team_member, team: advogados, user: brenda) }

  def setor = described_class.find_by!(chave: "setor:#{advogados.id}")
  def geral = described_class.find_by!(chave: 'geral')

  it 'garante Geral e um canal por time; cada um vê só onde participa, o administrador vê todos' do
    expect(described_class.visiveis(account, brenda, admin: false).map(&:tipo)).to contain_exactly('geral', 'setor')
    expect(described_class.visiveis(account, gabriela, admin: false).map(&:tipo)).to eq(['geral'])
    described_class.direto!(account, brenda, gabriela)
    expect(described_class.visiveis(account, admin, admin: true).map(&:tipo)).to contain_exactly('geral', 'setor', 'direto')
    expect(described_class.count).to eq(3)
  end

  it 'setor = membros do time; geral = usuários da conta' do
    described_class.garantir_fixos!(account)
    expect(setor.membro_ids).to eq([brenda.id])
    expect(geral.membro_ids).to contain_exactly(admin.id, brenda.id, gabriela.id)
  end

  it 'canal de setor de time apagado some da lista' do
    described_class.garantir_fixos!(account)
    advogados.destroy!
    expect(described_class.visiveis(account, admin, admin: true).map(&:tipo)).to eq(['geral'])
  end

  it 'direto é um só por par, nos dois sentidos' do
    canal = described_class.direto!(account, brenda, gabriela)
    expect(described_class.direto!(account, gabriela, brenda)).to eq(canal)
    expect(canal.membro_ids).to contain_exactly(brenda.id, gabriela.id)
    expect(canal.push_data(brenda)).to include(nome: gabriela.name, participante: true)
    expect(described_class.find(canal.id).push_data(admin)).to include(participante: false, nao_lidas: 0)
  end

  it 'não-lidas: só as dos outros, depois do lido_ate' do
    canal = described_class.direto!(account, brenda, gabriela)
    canal.mensagens.create!(autor: brenda, conteudo: 'oi')
    canal.mensagens.create!(autor: gabriela, conteudo: 'olá')
    expect(canal.nao_lidas(brenda)).to eq(1)
    travel(1.second) { canal.marcar_lido!(brenda) }
    expect(described_class.find(canal.id).nao_lidas(brenda)).to eq(0)
    expect(canal.nao_lidas(gabriela)).to eq(1)
  end

  it 'administrador marcando lido em 1:1 alheio não vira membro' do
    canal = described_class.direto!(account, brenda, gabriela)
    canal.marcar_lido!(admin)
    expect(canal.membros.pluck(:user_id)).to contain_exactly(brenda.id, gabriela.id)
  end

  it 'mensagem nova vai ao vivo pros membros e pros administradores' do
    canal = described_class.direto!(account, brenda, gabriela)
    expect { canal.mensagens.create!(autor: brenda, conteudo: 'oi') }
      .to have_enqueued_job(ActionCableBroadcastJob)
      .with(contain_exactly(brenda.pubsub_token, gabriela.pubsub_token, admin.pubsub_token), 'ramon.chat.message', hash_including(conteudo: 'oi'))
  end
end
