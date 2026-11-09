require 'rails_helper'

# Todo campo do esquema precisa de rótulo no painel (pt_BR e en).
describe Ramon::Colheita::Esquema do
  %w[en pt_BR].each do |locale|
    it "tem rótulo #{locale} para todo campo de todo bloco" do
      json = JSON.parse(Rails.root.join("app/javascript/dashboard/i18n/locale/#{locale}/ramon.json").read)
      campos = json.dig('RAMON', 'COLHEITA', 'CAMPO')
      caminhos = described_class::BLOCOS.keys.flat_map { |bloco| described_class.campos(bloco) }
      faltando = caminhos.reject { |caminho| campos.dig(*caminho.split('.')).is_a?(String) }
      expect(faltando).to eq([])
    end
  end
end
