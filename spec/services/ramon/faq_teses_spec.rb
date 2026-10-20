require 'rails_helper'

# Roda no CI FOSS (sem enterprise/): a FAQ aqui é um model de teste sobre a mesma tabela.
RSpec.describe Ramon::FaqTeses do
  let(:account) { create(:account) }
  let(:faqs) { stub_const('FaqTesesSpecFaq', Class.new(ApplicationRecord) { self.table_name = 'captain_assistant_responses' }) }
  let(:nomes_do_seed) do
    YAML.safe_load(Rails.root.join('db/seeds/ramon/theses_seed.yml').read).fetch('theses').pluck('name')
  end

  def faq(question, geral: false, thesis_ids: [])
    faqs.create!(account_id: account.id, assistant_id: 1, question: question, answer: 'x', geral: geral, thesis_ids: thesis_ids)
  end

  describe '.do_slug' do
    # a conta nova já pode nascer com teses do seed padrão: cria só as que faltam
    before do
      nomes_do_seed.each_with_index do |nome, i|
        create(:thesis, account: account, name: nome, position: i) unless Thesis.exists?(account_id: account.id, name: nome)
      end
    end

    def nomes(slug) = Thesis.where(id: described_class.do_slug(account, slug)[:thesis_ids]).pluck(:name)

    it 'cada arquivo do seed de FAQ vira tese real da conta (ou Geral)', :aggregate_failures do
      slugs = Dir[Rails.root.join('db/seeds/ramon/inteligencia/faq/*.md')].map { |arquivo| File.basename(arquivo, '.md') }
      expect(slugs - [described_class::GERAL]).to match_array(described_class::SLUGS.keys)
      described_class::SLUGS.each_key { |slug| expect([slug, nomes(slug)]).not_to eq([slug, []]) }
    end

    it 'trabalhista = as 4 teses "Trabalhista — …"; o resto, uma tese cada; geral = flag', :aggregate_failures do
      expect(nomes('trabalhista').size).to eq(4)
      expect(nomes('auxilio-acidente')).to eq(['Auxílio-acidente (B36)'])
      expect(nomes('auxilio-doenca').first).to start_with('Auxílio por incapacidade temporária')
      expect(described_class.do_slug(account, 'geral')).to eq(geral: true, thesis_ids: [])
      expect(described_class.do_slug(account, 'nao-existe')).to eq(geral: false, thesis_ids: [])
    end

    it 'casa o nome sem acento e não olha teses de outra conta' do
      outra = create(:account)
      sem_acento = create(:thesis, account: outra, name: 'Auxilio-acidente')
      expect(described_class.do_slug(outra, 'auxilio-acidente')[:thesis_ids]).to eq([sem_acento.id])
    end
  end

  describe 'filtros' do
    let!(:da_tese) { faq('Da tese 7?', thesis_ids: [7, 8]) }
    let!(:de_outra) { faq('De outra?', thesis_ids: [9]) }
    let!(:geral) { faq('Geral?', geral: true) }
    let!(:sem) { faq('Sem?') }

    it 'para_tese: as da tese do lead + Gerais + sem tese; lead sem tese = todas' do
      expect(described_class.para_tese(faqs.all, 7)).to contain_exactly(da_tese, geral, sem)
      expect(described_class.para_tese(faqs.all, nil)).to contain_exactly(da_tese, de_outra, geral, sem)
    end

    it 'filtrar (tela): geral, sem tese, id da tese; slug antigo = todas', :aggregate_failures do
      expect(described_class.filtrar(faqs.all, 'geral')).to contain_exactly(geral)
      expect(described_class.filtrar(faqs.all, 'sem')).to contain_exactly(sem)
      expect(described_class.filtrar(faqs.all, '8')).to contain_exactly(da_tese)
      expect(described_class.filtrar(faqs.all, 'bpc-loas').count).to eq(4)
    end
  end

  describe '.tese_do_turno' do
    let(:tese) { create(:thesis, account: account) }

    it 'Testar com roteiro: a tese do lead descartável; atendimento: a do lead da conversa' do
      conversa = create(:conversation, account: account)
      create(:lead, account: account, thesis: tese, conversation_id: conversa.id)

      expect(described_class.tese_do_turno(account.id, { roteiro_teste: { 'thesis_id' => 5 } })).to eq(5)
      expect(described_class.tese_do_turno(account.id, { conversation: { id: conversa.id } })).to eq(tese.id)
      expect(described_class.tese_do_turno(create(:account).id, { conversation: { id: conversa.id } })).to be_nil
      expect(described_class.tese_do_turno(account.id, {})).to be_nil
    end
  end
end
