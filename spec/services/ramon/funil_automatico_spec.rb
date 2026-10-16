require 'rails_helper'

RSpec.describe Ramon::FunilAutomatico do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }
  let(:args) { { peca: 'etapa_ia', acao: 'mover', motivo: 'pediu reunião', alvo: 'fase-qualificacao' } }

  def ligar(modo) = described_class.mudar!(account, 'etapa_ia', modo)

  describe '.modo / .mudar!' do
    it 'começa off e grava a chave sob settings[funil_automatico]' do
      expect(described_class.modo(account, 'etapa_ia')).to eq('off')
      ligar('ensaio')
      expect(described_class.modo(account.reload, 'etapa_ia')).to eq('ensaio')
      expect(account.settings['funil_automatico']).to eq('etapa_ia' => 'ensaio')
    end

    it 'rejeita peça ou modo inválido' do
      expect { described_class.mudar!(account, 'xyz', 'on') }.to raise_error(ArgumentError)
      expect { described_class.mudar!(account, 'etapa_ia', 'talvez') }.to raise_error(ArgumentError)
    end
  end

  describe '.executar' do
    it 'em off devolve nil, não grava e não roda o bloco' do
      expect { |b| expect(described_class.executar(lead, **args, &b)).to be_nil }.not_to yield_control
      expect(FunilAcao.count).to eq(0)
    end

    it 'em ensaio grava com ensaio true e não roda o bloco' do
      ligar('ensaio')
      resultado = nil
      expect { |b| resultado = described_class.executar(lead, **args, &b) }.not_to yield_control
      expect(resultado).to be_ensaio
      expect(FunilAcao.count).to eq(1)
      expect(LeadActivity.where(kind: 'funil_auto')).to be_empty
    end

    it 'em on roda o bloco, grava ensaio false e cria a marca no histórico' do
      ligar('on')
      resultado = nil
      expect { |b| resultado = described_class.executar(lead, **args, &b) }.to yield_control
      expect(resultado).to have_attributes(ensaio: false, peca: 'etapa_ia', acao: 'mover', alvo: 'fase-qualificacao')
      expect(LeadActivity.where(kind: 'funil_auto').count).to eq(1)
      expect(LeadActivity.find_by(kind: 'funil_auto').to_value).to eq('mover: pediu reunião')
    end

    it 'em on, a marca no histórico sai sem usuário mesmo com alguém logado (é da automação)' do
      ligar('on')
      Current.user = create(:user, account: account)
      described_class.executar(lead, **args) { true }
      expect(LeadActivity.find_by(kind: 'funil_auto').user_id).to be_nil
    ensure
      Current.reset
    end

    it 'em on, bloco que devolve false não grava nada' do
      ligar('on')
      expect(described_class.executar(lead, **args) { false }).to be_nil
      expect(FunilAcao.count).to eq(0)
      expect(LeadActivity.where(kind: 'funil_auto')).to be_empty
    end
  end

  describe '.desfeita_recente?' do
    let(:conversation) { create(:conversation, account: account) }

    before do
      lead.update!(conversation: conversation)
      FunilAcao.create!(account: account, lead: lead, peca: 'etapa_ia', acao: 'mover', alvo: 'fase-qualificacao',
                        desfeita_em: 1.hour.ago)
    end

    it 'é true enquanto não há mensagem nova do lead' do
      expect(described_class.desfeita_recente?(lead, acao: 'mover', alvo: 'fase-qualificacao')).to be(true)
    end

    it 'é false depois de uma incoming criada após desfeita_em' do
      create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :incoming)
      expect(described_class.desfeita_recente?(lead, acao: 'mover', alvo: 'fase-qualificacao')).to be(false)
    end

    it 'é false para outra ação/alvo' do
      expect(described_class.desfeita_recente?(lead, acao: 'mover', alvo: 'fase-negociacao')).to be(false)
    end
  end
end
