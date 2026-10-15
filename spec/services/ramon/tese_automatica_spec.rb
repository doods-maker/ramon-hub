require 'rails_helper'

RSpec.describe Ramon::TeseAutomatica do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, auto_create_lead: true) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:lead) { create(:lead, account: account, conversation: conversation, contact: conversation.contact) }
  # Toda conta nasce com as teses do theses_seed.yml (Leads::SeedDefaultConfigService).
  let!(:acidente) do
    account.theses.find_by!(name: 'Auxílio-acidente (B36)').tap { |t| t.update!(palavras_chave: ['auxílio-acidente', 'acidente de trabalho']) }
  end
  let!(:bpc) { account.theses.find_by!(name: 'BPC/LOAS (idoso ou pessoa com deficiência)').tap { |t| t.update!(palavras_chave: %w[bpc loas]) } }

  def mensagem(texto, **attrs)
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: texto, **attrs)
  end

  describe '.por_texto' do
    it 'casa palavra ou frase inteira, sem acento nem caixa' do
      expect(described_class.por_texto(account, 'Sofri um ACIDENTE DE TRABALHO')).to eq(acidente)
      expect(described_class.por_texto(account, 'quero o Bpc da minha filha')).to eq(bpc)
      expect(described_class.por_texto(account, 'sou bpcista')).to be_nil
    end

    # Review Focus 2: tese errada é pior que nenhuma.
    it 'duas teses = não escolhe; tese inativa não conta; nada = nil' do
      expect(described_class.por_texto(account, 'tenho bpc e sofri acidente de trabalho')).to be_nil
      bpc.update!(active: false)
      expect(described_class.por_texto(account, 'tenho bpc e sofri acidente de trabalho')).to eq(acidente)
      expect(described_class.por_texto(account, nil, 'oi, tudo bem?')).to be_nil
    end

    it 'slug da campanha da LP casa com a palavra-chave' do
      expect(described_class.por_texto(account, 't-auxilio-acidente-desqualificado')).to eq(acidente)
    end
  end

  describe '.definir' do
    it '1ª mensagem com palavra-chave define a tese e vence a tese da caixa' do
      inbox.update!(ramon_thesis_id: bpc.id)
      described_class.definir(lead, mensagem('me acidentei, foi acidente de trabalho'))
      expect(lead.reload.thesis).to eq(acidente)
    end

    it 'sem palavra-chave: tese padrão da caixa' do
      inbox.update!(ramon_thesis_id: bpc.id)
      described_class.definir(lead, mensagem('oi, boa tarde'))
      expect(lead.reload.thesis).to eq(bpc)
    end

    it 'tese padrão da caixa que pertence a outra conta é ignorada' do
      outra_tese = create(:account).theses.first
      inbox.update!(ramon_thesis_id: outra_tese.id)
      described_class.definir(lead, mensagem('oi, boa tarde'))
      expect(lead.reload.thesis).to be_nil
    end

    it 'campanha da LP e título do anúncio da Meta contam' do
      lead.update!(source: 'bpc-loas')
      described_class.definir(lead, mensagem('oi'))
      expect(lead.reload.thesis).to eq(bpc)

      outra = create(:conversation, account: account, inbox: inbox)
      lead2 = create(:lead, account: account, conversation: outra, contact: outra.contact)
      anuncio = create(:message, account: account, conversation: outra, message_type: :incoming, content: 'oi',
                                 content_attributes: { referral: { 'headline' => 'Machucou no trabalho? Acidente de trabalho' } })
      described_class.definir(lead2, anuncio)
      expect(lead2.reload.thesis).to eq(acidente)
    end

    # Review Focus 3: a tese nunca é trocada nem decidida depois da 1ª mensagem.
    it 'só na 1ª mensagem e só para lead sem tese' do
      mensagem('oi')
      described_class.definir(lead, mensagem('acidente de trabalho'))
      expect(lead.reload.thesis).to be_nil

      outra = create(:conversation, account: account, inbox: inbox)
      com_tese = create(:lead, account: account, conversation: outra, contact: outra.contact, thesis: bpc)
      primeira = create(:message, account: account, conversation: outra, message_type: :incoming, content: 'acidente de trabalho')
      described_class.definir(com_tese, primeira)
      expect(com_tese.reload.thesis).to eq(bpc)
    end
  end
end
