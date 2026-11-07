require 'rails_helper'

RSpec.describe Ramon::MetaGastoCsv do
  let(:account) { create(:account) }

  let(:csv_pt) do
    <<~CSV
      \uFEFFNome da campanha;Nome do conjunto de anúncios;Nome do anúncio;Dia;Valor usado (BRL);Impressões;Cliques no link;Resultados;Indicador de resultados;Identificação da campanha;Identificação do conjunto de anúncios;Identificação do anúncio
      Auxílio;Conjunto A;Anúncio 1;2026-10-14;1.234,56;10.500;120;33;actions:onsite_conversion.messaging_conversation_started_7d;c1;s1;111
      Auxílio;Conjunto A;Anúncio 2;2026-10-14;10,50;900;8;2;actions:lead;c1;s1;222
      ;;;;1.245,06;11.400;128;;;;;
    CSV
  end

  it 'grava o CSV em português com ; e decimal com vírgula, pulando a linha de total' do
    expect(described_class.importar(account, csv_pt)).to eq(2)

    um = MetaGasto.find_by!(account: account, ad_id: '111')
    expect(um).to have_attributes(data: Date.new(2026, 10, 14), spend: BigDecimal('1234.56'), impressions: 10_500, clicks: 120,
                                  conversas: 33, leads_meta: 0, adset_id: 's1', campaign_id: 'c1', origem: 'csv')
    expect(MetaGasto.find_by!(ad_id: '222')).to have_attributes(conversas: 0, leads_meta: 2)
  end

  it 'aceita o CSV em inglês com , e data dd/mm/aaaa' do
    csv = "Ad ID,Ad name,Day,Amount spent (BRL),Impressions\n333,Ad,14/10/2026,\"1,234.56\",\"1,000\"\n"
    described_class.importar(account, csv)
    expect(MetaGasto.find_by!(ad_id: '333')).to have_attributes(data: Date.new(2026, 10, 14), spend: BigDecimal('1234.56'), impressions: 1000)
  end

  it 'reimportar o mesmo anúncio e dia atualiza sem duplicar' do
    described_class.importar(account, csv_pt)
    described_class.importar(account, csv_pt.sub('10,50', '12,00'))
    expect(MetaGasto.where(account: account).count).to eq(2)
    expect(MetaGasto.find_by!(ad_id: '222').spend).to eq(BigDecimal('12.00'))
  end

  it 'sem a coluna Dia ou ID do anúncio explica como exportar' do
    expect { described_class.importar(account, "Nome do anúncio,Valor usado (BRL)\nA,10\n") }
      .to raise_error(described_class::Erro, /Faltam colunas: dia, identificacao do anuncio.*detalhamento por Dia/)
  end
end
