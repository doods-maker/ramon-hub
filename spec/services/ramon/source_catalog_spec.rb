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

  describe '.derive_from_message' do
    it 'derives google_seo from the institutional site signature' do
      expect(described_class.derive_from_message('Olá! Vim pelo site do escritório e gostaria de falar com a equipe.'))
        .to eq(%w[google_seo site-institucional])
    end

    it 'derives landing_page from the classic LP signature' do
      expect(described_class.derive_from_message('Olá, vim pelo site e gostaria de tirar dúvidas sobre o auxílio-acidente.'))
        .to eq(%w[landing_page lp:whatsapp])
    end

    it 'derives landing_page from the triage quiz signature' do
      expect(described_class.derive_from_message("Olá! Fiz a triagem de auxílio-acidente no site.\nTriagem — Auxílio-acidente"))
        .to eq(%w[landing_page lp:triagem])
    end

    it 'derives instagram from the bio link signature' do
      expect(described_class.derive_from_message('Olá! Vim pelo Instagram e quero avaliar meu caso.'))
        .to eq(%w[instagram instagram-bio])
    end

    it 'returns nil for unsigned text' do
      expect(described_class.derive_from_message('oi, tudo bem?')).to be_nil
    end

    it 'returns nil for blank text' do
      expect(described_class.derive_from_message(nil)).to be_nil
    end
  end
end
