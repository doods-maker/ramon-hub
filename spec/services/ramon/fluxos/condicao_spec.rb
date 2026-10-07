require 'rails_helper'

RSpec.describe Ramon::Fluxos::Condicao do
  let(:dados) { { 'tese' => 'Auxílio-acidente', 'valor' => 5000.0, 'etiquetas' => %w[urgente vip], 'origem' => nil } }

  def se(condicoes, juncao = 'e') = described_class.avaliar({ 'condicoes' => condicoes, 'juncao' => juncao }, dados)

  it 'compara sem acento e sem caixa' do
    expect(se([{ 'campo' => 'tese', 'operador' => 'igual', 'valor' => 'auxilio-acidente' }])).to be(true)
    expect(se([{ 'campo' => 'tese', 'operador' => 'contem', 'valor' => 'ACIDENTE' }])).to be(true)
    expect(se([{ 'campo' => 'tese', 'operador' => 'diferente', 'valor' => 'BPC' }])).to be(true)
  end

  it 'lista, número, existe/vazio e E/OU' do
    expect(se([{ 'campo' => 'etiquetas', 'operador' => 'igual', 'valor' => 'vip' }])).to be(true)
    expect(se([{ 'campo' => 'valor', 'operador' => 'maior', 'valor' => '1000' }])).to be(true)
    expect(se([{ 'campo' => 'origem', 'operador' => 'vazio' }])).to be(true)
    falsa = { 'campo' => 'origem', 'operador' => 'existe' }
    verdadeira = { 'campo' => 'tese', 'operador' => 'existe' }
    expect(se([falsa, verdadeira], 'e')).to be(false)
    expect(se([falsa, verdadeira], 'ou')).to be(true)
  end

  it 'escolha devolve a chave do caso ou outro' do
    config = { 'campo' => 'tese', 'casos' => [
      { 'chave' => 'c1', 'rotulo' => 'BPC', 'valores' => ['BPC'] },
      { 'chave' => 'c2', 'rotulo' => 'Acidente', 'valores' => %w[Auxílio-acidente Auxílio-doença] }
    ] }
    expect(described_class.escolher(config, dados)).to eq('c2')
    expect(described_class.escolher(config, { 'tese' => 'Aposentadoria' })).to eq('outro')
  end

  it 'agora é horário comercial: usa a janela da própria condição (B4.2)' do
    travel_to(Time.find_zone!('America/Sao_Paulo').parse('2026-10-10 20:30')) do # sábado, 20h30
      padrao = { 'campo' => 'status', 'operador' => 'em_horario_comercial', 'valor' => '' }
      expect(described_class.teste(padrao, {})).to be(false)
      expect(described_class.teste(padrao.merge('dias' => (0..6).to_a, 'inicio' => 7, 'fim' => 21), {})).to be(true)
    end
  end
end
