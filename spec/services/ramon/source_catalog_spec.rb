require 'rails_helper'

RSpec.describe Ramon::SourceCatalog do
  describe '.derive' do
    it 'classifica anuncio-meta como meta_ads' do
      expect(described_class.derive('anuncio-meta: 12345')).to eq('meta_ads')
    end

    it 'classifica indicação' do
      expect(described_class.derive('Indicação de cliente')).to eq('indicacao')
    end

    it 'classifica instagram' do
      expect(described_class.derive('campanha instagram julho')).to eq('instagram')
    end

    it 'classifica google/seo' do
      expect(described_class.derive('Google Ads')).to eq('google_seo')
    end

    it 'retorna nil sem regra que casa ou com source em branco' do
      expect(described_class.derive('campanha desconhecida')).to be_nil
      expect(described_class.derive('')).to be_nil
      expect(described_class.derive(nil)).to be_nil
    end
  end

  describe '.valid? e .labels' do
    it 'expõe as 7 chaves fixas na ordem da taxonomia' do
      expect(described_class.labels.keys).to eq(
        %w[meta_ads landing_page instagram google_seo indicacao whatsapp_direto outro]
      )
      expect(described_class.valid?('meta_ads')).to be true
      expect(described_class.valid?('inexistente')).to be false
    end
  end
end
