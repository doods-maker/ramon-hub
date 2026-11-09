require 'rails_helper'

RSpec.describe Ramon::Colheita::Esquema do
  it 'B31 = núcleo + segurado, saude, incapacidade' do
    expect(described_class.blocos_para('Auxílio por incapacidade temporária (auxílio-doença / B31)'))
      .to eq(%w[cliente beneficios fechamento outras_teses_sinal segurado saude incapacidade])
  end

  it 'acréscimo de 25% não cai no B32 por conter "invalidez"' do
    expect(described_class.tese('Acréscimo de 25% (grande invalidez)')).to eq(:acrescimo25)
    blocos = described_class.blocos_para('Acréscimo de 25% (grande invalidez)')
    expect(blocos).to include('dependencia')
    expect(blocos).not_to include('incapacidade')
  end

  it 'mapeia as 11 teses do hub' do
    {
      'Aposentadoria por incapacidade permanente (invalidez / B32)' => :b32, 'Auxílio-acidente (B36)' => :b36,
      'BPC/LOAS (idoso ou pessoa com deficiência)' => :bpc, 'Salário-maternidade' => :maternidade,
      'Isenção de IR por doença grave' => :ir, 'Trabalhista — acidente ou doença do trabalho' => :trab_acidente,
      'Trabalhista — rescisão indireta' => :trab_rescisao, 'Trabalhista — reconhecimento de vínculo' => :trab_vinculo,
      'Trabalhista — direito suprimido' => :trab_suprimido
    }.each { |nome, chave| expect(described_class.tese(nome)).to eq(chave), nome }
  end

  it 'trabalhista de acidente reaproveita acidente e sequela do B36' do
    expect(described_class.blocos_para('Trabalhista — acidente ou doença do trabalho'))
      .to eq(%w[cliente beneficios fechamento outras_teses_sinal contrato acidente sequela responsabilidade])
  end

  it 'tese fora do mapa extrai só o núcleo' do
    expect(described_class.blocos_para('Tese inventada')).to eq(described_class::NUCLEO)
  end

  it 'o modelo do prompt traz só os blocos da tese, com representante e testemunhas' do
    b31 = JSON.parse(described_class.modelo_json('Auxílio por incapacidade temporária (auxílio-doença / B31)'))
    expect(b31.keys).to include('incapacidade', 'confirmar', 'lacunas', 'checklist_ok')
    expect(b31.keys).not_to include('acidente')
    expect(b31.dig('cliente', 'representante').keys).to eq(%w[nome parentesco motivo])
    vinculo = JSON.parse(described_class.modelo_json('Trabalhista — reconhecimento de vínculo'))
    expect(vinculo.dig('contrato', 'testemunhas', 0).keys).to eq(%w[nome relacao])
  end

  it 'campos lista o 1º nível; bloco-lista entra inteiro; todo bloco do mapa existe' do
    expect(described_class.campos('fechamento')).to include('fechamento.objecoes')
    expect(described_class.campos('beneficios')).to eq(%w[beneficios])
    described_class::TESES.flat_map(&:last).each { |bloco| expect(described_class::BLOCOS).to have_key(bloco) }
  end
end
