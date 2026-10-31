require 'rails_helper'

RSpec.describe Ramon::Equipe do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:ana) { create(:user, account: account) }
  let!(:bia) { create(:user, account: account) }
  let!(:recepcao) { create(:team, account: account, name: 'recepcao') }

  def participantes(conversa) = conversa.conversation_participants.pluck(:user_id).sort

  def conversa(chave) = described_class.caixa(account).contact_inboxes.find_by!(source_id: "equipe-#{chave}").conversations.first

  describe '.sincronizar' do
    before { create(:team_member, team: recepcao, user: ana) }

    it 'cria a caixa Equipe com o Geral (todos) e um canal por time (membros), sem lead nem atribuição automática' do
      inbox = described_class.sincronizar(account, criar: true)

      expect(inbox).to have_attributes(equipe: true, channel_type: 'Channel::Api', enable_auto_assignment: false)
      expect(participantes(conversa('geral'))).to eq([admin.id, ana.id, bia.id].sort)
      expect(participantes(conversa("time-#{recepcao.id}"))).to eq([ana.id])
      expect(conversa("time-#{recepcao.id}").contact).to have_attributes(name: 'Setor recepcao')
      expect(account.leads.count).to eq(0)
    end

    it 'é idempotente' do
      2.times { described_class.sincronizar(account, criar: true) }

      expect(account.inboxes.where(equipe: true).count).to eq(1)
      expect(account.conversations.count).to eq(2)
    end

    it 'sem criar: não faz nada onde a caixa não existe' do
      expect(described_class.sincronizar(account)).to be_nil
      expect(account.inboxes.where(equipe: true)).to be_empty
    end

    it 'acompanha quem entra e sai do time e da conta' do
      described_class.sincronizar(account, criar: true)

      create(:team_member, team: recepcao, user: bia)
      recepcao.team_members.find_by(user: ana).destroy!
      novo = create(:user, account: account)

      expect(participantes(conversa("time-#{recepcao.id}"))).to eq([bia.id])
      expect(participantes(conversa('geral'))).to include(novo.id)
    end
  end

  describe '.conversa_1a1' do
    before { described_class.sincronizar(account, criar: true) }

    it 'é a mesma conversa nos dois sentidos, só com as duas pessoas' do
      ida = described_class.conversa_1a1(account, ana, bia)

      expect(described_class.conversa_1a1(account, bia, ana)).to eq(ida)
      expect(participantes(ida)).to eq([ana.id, bia.id].sort)
    end
  end

  describe '.nao_lidas' do
    let(:geral) { described_class.sincronizar(account, criar: true) && conversa('geral') }

    it 'conta só mensagem de colega depois da última leitura, por pessoa' do
      create(:message, conversation: geral, account: account, inbox: geral.inbox, sender: ana, message_type: :outgoing)
      described_class.marcar_lida(geral, bia)
      travel 1.minute
      create(:message, conversation: geral, account: account, inbox: geral.inbox, sender: ana, message_type: :outgoing)

      expect(described_class.nao_lidas(geral, bia)).to eq(1)
      expect(described_class.nao_lidas(geral, admin)).to eq(2)
      expect(described_class.nao_lidas(geral, ana)).to eq(0)
      expect(described_class.total_nao_lidas(account, bia)).to eq(1)
    end
  end

  describe '.evento?' do
    it 'reconhece conversa, mensagem, contato e caixa da Equipe' do
      inbox = described_class.sincronizar(account, criar: true)
      geral = conversa('geral')
      message = create(:message, conversation: geral, account: account, inbox: inbox, sender: ana, message_type: :outgoing)

      eventos = [{ conversation: geral }, { message: message }, { contact: geral.contact }, { inbox: inbox }]

      expect(eventos.map { |data| described_class.evento?(data) }).to all(be(true))
      expect(described_class.evento?(conversation: create(:conversation, account: account))).to be(false)
      expect(described_class.evento?(contact: create(:contact, account: account))).to be(false)
    end
  end
end
