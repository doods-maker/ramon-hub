require 'rails_helper'

RSpec.describe Ramon::IaLimites do
  let(:account) { create(:account) }

  def salvar(valor) = account.update!(settings: { 'ia_limites' => valor })

  # o caminho da escrita: o fragmento validado entra no settings (a tela faz isso junto com o Perfil, em Ramon::PerfilIa.gravar!)
  def gravar!(limites) = account.update!(settings: Hash(account.settings).merge(described_class.fragmento!(account, limites)))

  describe '.de' do
    it 'sem nada salvo (ou sem conta) devolve os valores de hoje', :aggregate_failures do
      padrao = { horario: { 'dias' => [1, 2, 3, 4, 5], 'janelas' => [%w[08:30 12:00], %w[13:30 18:00]] }, atraso: 30..180,
                 fluxo_ia_dia: 200, retomadas_dia: 15, retomada_intervalo_dias: 5 }
      expect(described_class.de(account)).to eq(padrao)
      expect(described_class.de(nil)).to eq(padrao)
    end

    it 'fluxo_ia_dia ausente segue o env RAMON_FLUXO_IA_DIA' do
      with_modified_env(RAMON_FLUXO_IA_DIA: '7') { expect(described_class.de(account)[:fluxo_ia_dia]).to eq(7) }
    end

    it 'lê o salvo e ignora valor venenoso', :aggregate_failures do
      salvar('atraso' => { 'min' => 5, 'max' => 10 }, 'retomadas_dia' => 20, 'horario' => 'x', 'fluxo_ia_dia' => 'muito')
      limites = described_class.de(account)
      expect(limites).to include(atraso: 5..10, retomadas_dia: 20, fluxo_ia_dia: 200)
      expect(limites[:horario]['dias']).to eq([1, 2, 3, 4, 5])
    end
  end

  describe '.corpo' do
    it 'diz se o fluxo de cadência está no comando (retomadas_dia deixa de valer)', :aggregate_failures do
      expect(described_class.corpo(account)).to include(retomadas_no_fluxo: false)
      allow(Ramon::Fluxos::Retomada).to receive(:assumiu?).with(account).and_return(true)
      expect(described_class.corpo(account)).to include(retomadas_no_fluxo: true)
    end
  end

  describe '.fragmento!' do
    it 'grava parcial sem apagar o resto e o teto em US$ na chave do alerta', :aggregate_failures do
      gravar!({ 'retomadas_dia' => 20 })
      gravar!({ 'atraso' => { 'min' => 10, 'max' => 60 }, 'teto_usd' => '2,5' })
      account.reload
      expect(account.settings['ia_limites']).to eq('retomadas_dia' => 20, 'atraso' => { 'min' => 10, 'max' => 60 })
      expect(Ramon::IaGastoAlerta.teto(account)).to eq(2.5)

      gravar!({ 'teto_usd' => nil })
      expect(Ramon::IaGastoAlerta.teto(account.reload)).to be_nil
    end

    it 'recusa o inválido com motivo e não grava', :aggregate_failures do
      invalidos = [
        { 'atraso' => { 'min' => 30, 'max' => 200 } }, { 'atraso' => { 'min' => 90, 'max' => 60 } },
        { 'atraso' => { 'min' => -1, 'max' => 60 } }, { 'atraso' => { 'min' => 30 } },
        { 'horario' => { 'dias' => [], 'janelas' => [%w[08:00 12:00]] } },
        { 'horario' => { 'dias' => [1, 7], 'janelas' => [%w[08:00 12:00]] } },
        { 'horario' => { 'dias' => [1], 'janelas' => [] } },
        { 'horario' => { 'dias' => [1], 'janelas' => [%w[12:00 08:00]] } },
        { 'horario' => { 'dias' => [1], 'janelas' => [%w[8:00 12:00]] } },
        { 'horario' => { 'dias' => [1], 'janelas' => [%w[13:00 18:00], %w[08:00 12:00]] } },
        { 'horario' => { 'dias' => [1], 'janelas' => [%w[08:00 12:30], %w[12:00 18:00]] } },
        { 'horario' => { 'dias' => [1], 'janelas' => [%w[08:00 09:00], %w[10:00 11:00], %w[12:00 13:00]] } },
        { 'fluxo_ia_dia' => 0 }, { 'retomadas_dia' => 1001 }, { 'retomada_intervalo_dias' => 61 }, { 'retomadas_dia' => '15' },
        { 'teto_usd' => -1 }, { 'teto_usd' => 'caro' }, 'nada'
      ]
      invalidos.each do |corpo|
        expect { gravar!(corpo) }.to raise_error(ArgumentError, /\S/)
      end
      expect(account.reload.settings['ia_limites']).to be_nil
    end

    it 'valor salvo que não é Hash não derruba a escrita' do
      salvar('texto solto')
      gravar!({ 'retomadas_dia' => 20 })
      expect(account.reload.settings['ia_limites']).to eq('retomadas_dia' => 20)
    end

    it 'duas faixas encostadas (fim = início) valem' do
      gravar!({ 'horario' => { 'dias' => [6, 0, 6], 'janelas' => [%w[08:00 12:00], %w[12:00 14:00]] } })
      expect(described_class.de(account.reload)[:horario]).to eq('dias' => [0, 6], 'janelas' => [%w[08:00 12:00], %w[12:00 14:00]])
    end
  end
end
