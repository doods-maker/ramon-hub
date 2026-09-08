# spec/lib/ramon/portal_texto_spec.rb
require 'rails_helper'

RSpec.describe Ramon::PortalTexto do
  it 'traduz etapa conhecida (case/acento insensível)' do
    etapa = described_class.etapa('Pericia Agendada')
    expect(etapa['titulo']).to eq 'Perícia agendada'
    expect(etapa['o_que_esperar']).to be_present
  end

  it 'etapa desconhecida cai no texto neutro' do
    expect(described_class.etapa('ETAPA NOVA')['titulo']).to eq 'Etapa nova'
    expect(described_class.etapa(nil)['titulo']).to eq 'Em andamento'
  end

  it 'cobre todas as etapas da conta (settings de 08/09/2026)' do
    etapas = YAML.load_file(Rails.root.join('spec/fixtures/advbox_stages.yml'))
    faltando = etapas.reject { |nome| described_class::ETAPAS.key?(described_class.normalizar(nome)) }
    expect(faltando).to eq([])
  end

  it 'reconhece marcos e mantém só o mais recente de cada tipo, em ordem cronológica' do
    andamentos = [
      { 'data' => '2026-03-01', 'titulo' => 'Juntada de petição' },
      { 'data' => '2026-04-10', 'titulo' => 'Perícia médica designada' },
      { 'data' => '2026-06-01', 'titulo' => 'Perícia realizada' },
      { 'data' => '2026-08-15', 'titulo' => 'Sentença proferida' }
    ]
    marcos = described_class.marcos(andamentos)
    expect(marcos.map { |m| m['tipo'] }).to eq %w[pericia sentenca]
    expect(marcos.first['data']).to eq '2026-06-01'
  end

  it 'encerrado só na fase ARQUIVAMENTO' do
    expect(described_class.encerrado?('ARQUIVAMENTO')).to be true
    expect(described_class.encerrado?('RH/FINANCEIRO')).to be false
  end
end
