require 'rails_helper'

RSpec.describe Ramon::EtapaDeGanho do
  # A conta seeda o funil no after_create (Novo ... Fechado is_won / Perdido is_lost).
  let(:account) { create(:account) }
  let(:fechado) { account.lead_stages.find_by!(label: described_class::FECHADO) }

  it 'principal é Fechado mesmo com outras etapas de ganho antes dela', :aggregate_failures do
    docs = account.lead_stages.create!(name: 'Docs X', label: described_class::DOCUMENTOS, is_won: true, position: -5)

    expect(described_class.principal(account)).to eq(fechado)
    expect(described_class.entrada(build(:lead, account: account))).to eq(fechado)
    expect(docs.reload).to be_is_won
  end

  it 'sem Fechado, a primeira etapa de ganho por posição' do
    fechado.update!(label: nil)
    primeira = account.lead_stages.create!(name: 'Ganho 1', is_won: true, position: -9)

    expect(described_class.principal(account)).to eq(primeira)
  end

  it 'sem etapa de ganho, principal é nil e principal! levanta', :aggregate_failures do
    expect(described_class.principal!(account)).to eq(fechado)
    account.lead_stages.update_all(is_won: false) # rubocop:disable Rails/SkipsModelValidations

    expect(described_class.principal(account)).to be_nil
    expect { described_class.principal!(account) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  describe '.entrada com a etapa Documentos' do
    let!(:documentos) { Ramon::EtapasPosVenda.criar!(account).first }
    let(:tese) { create(:thesis, account: account, name: 'Tese Spec Documentos', passa_documentos: true) }
    let(:lead) { build(:lead, account: account, thesis: tese) }

    before { create(:thesis_item, thesis: tese, section: 'documento', content: 'CNIS completo') }

    def ligada(&) = with_modified_env(RAMON_ETAPA_DOCUMENTOS: 'on', &)

    it 'chave ligada, tese que passa por Documentos e com item de documento: Documentos' do
      ligada { expect(described_class.entrada(lead)).to eq(documentos) }
    end

    it 'chave desligada: Fechado, mesmo para a tese que passa por Documentos' do
      expect(described_class.entrada(lead)).to eq(fechado)
    end

    it 'tese sem a chave, lead sem tese ou tese sem item de documento: Fechado', :aggregate_failures do
      outra = create(:thesis, account: account, name: 'Tese Spec Sem Chave')
      create(:thesis_item, thesis: outra, section: 'documento', content: 'RG')
      sem_item = create(:thesis, account: account, name: 'Tese Spec Sem Item', passa_documentos: true)
      create(:thesis_item, thesis: sem_item, section: 'abertura', content: 'Oi')

      ligada do
        expect(described_class.entrada(build(:lead, account: account, thesis: outra))).to eq(fechado)
        expect(described_class.entrada(build(:lead, account: account, thesis: nil))).to eq(fechado)
        expect(described_class.entrada(build(:lead, account: account, thesis: sem_item))).to eq(fechado)
      end
    end

    it 'conta sem a etapa Documentos: Fechado' do
      documentos.update!(label: nil)
      ligada { expect(described_class.entrada(lead)).to eq(fechado) }
    end

    # O ADVBOX do Ganho pergunta aqui se o 1º contato é do agente de documentos (spec §9).
    it '.pelo_agente_de_documentos?: o lead em Documentos ou já no Jurídico, com a chave ligada', :aggregate_failures do
      juridico = described_class.juridico(account)
      no = ->(etapa) { build(:lead, account: account, thesis: tese, lead_stage: etapa) }

      ligada do
        expect(described_class.pelo_agente_de_documentos?(no[documentos])).to be(true)
        expect(described_class.pelo_agente_de_documentos?(no[juridico])).to be(true)
        expect(described_class.pelo_agente_de_documentos?(no[fechado])).to be(false)
      end
      expect(described_class.pelo_agente_de_documentos?(no[documentos])).to be(false)
    end
  end
end
