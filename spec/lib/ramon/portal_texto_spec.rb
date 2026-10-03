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
    faltando = etapas.reject { |nome| described_class::V1['etapas'].key?(described_class.normalizar(nome)) }
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

  it 'andamento nunca vira "Benefício concedido" (concessão só pela etapa da equipe)' do
    textos = ['Benefício concedido', 'Deferida a gratuidade da justiça', 'Concedido prazo de 15 dias', 'Benefício indeferido']
    expect(textos.flat_map { |t| described_class.marcos([{ 'data' => '2026-09-01', 'titulo' => t }]) }).to be_empty
  end

  it 'assunto do processo sai do tipo do ADVBOX, sem código nem detalhe' do
    expect(described_class.assunto('AUXÍLIO-ACIDENTE - COMUM (B36)')).to eq 'Auxílio-acidente'
    expect(described_class.assunto('APOSENTADORIA POR IDADE - PCD (B41)')).to eq 'Aposentadoria por idade'
    expect(described_class.assunto('ISENÇÃO DE IRPF')).to eq 'Isenção de IRPF'
    expect(described_class.assunto('PROCEDIMENTO DO JUIZADO ESPECIAL CÍVEL')).to be_nil
    expect(described_class.assunto(nil)).to be_nil
  end

  it 'identificação: assunto + onde corre + número' do
    inss = { 'tipo' => 'AUXÍLIO-ACIDENTE - COMUM (B36)', 'numero' => '1234567890', 'fase' => 'ADMINISTRATIVO' }
    expect(described_class.identificacao(inss)).to eq ['Auxílio-acidente', 'Pedido no INSS · nº 1234567890']
    justica = { 'tipo' => 'PROCEDIMENTO DO JUIZADO ESPECIAL CÍVEL', 'numero' => '5003800-40.2022.4.04.7207', 'fase' => 'RECURSAL' }
    expect(described_class.identificacao(justica)).to eq ['Processo na Justiça', 'nº 5003800-40.2022.4.04.7207']
    sem_numero = { 'tipo' => 'PENSÃO POR MORTE - COMUM (B21)', 'numero' => nil, 'fase' => 'JUDICIAL' }
    expect(described_class.identificacao(sem_numero)).to eq ['Pensão por morte', 'Processo na Justiça']
  end

  it 'selo de status: verde só em etapa positiva da equipe; resultado em análise nunca vira verde' do
    expect(described_class.status({ 'etapa' => 'BENEFICIO CONCEDIDO / IMPLANTACAO', 'fase' => 'ADMINISTRATIVO' }))
      .to eq %w[aprovado Aprovado]
    expect(described_class.status({ 'etapa' => 'REQUERIMENTO PROTOCOLADO', 'fase' => 'ADMINISTRATIVO' })).to eq ['andamento', 'Em andamento']
    expect(described_class.status({ 'etapa' => 'ARQUIVADO/ENCERRADO', 'fase' => 'ARQUIVAMENTO' })).to eq %w[concluido Concluído]
  end

  it 'encerrado só na fase ARQUIVAMENTO' do
    expect(described_class.encerrado?('ARQUIVAMENTO')).to be true
    expect(described_class.encerrado?('RH/FINANCEIRO')).to be false
  end

  it 'sem a chave v2 toda etapa manda e-mail (v1 não tem a flag)' do
    expect(described_class.v2?).to be false
    expect(described_class.email?('REUNIAO POS VENDA')).to be true
  end

  context 'with PORTAL_TEXTOS_V2=on' do
    around { |ex| with_modified_env(PORTAL_TEXTOS_V2: 'on') { ex.run } }

    def processo(etapa, step) = { 'etapa' => etapa, 'fase' => step }

    it 'cobre as 61 etapas do ADVBOX de 28/09/2026: fase + texto, ou interna' do
      etapas = YAML.load_file(Rails.root.join('spec/fixtures/advbox_stages_v2.yml'))
      expect(etapas.size).to eq 61
      fases = described_class::V2['fases'].pluck('chave')
      faltando = etapas.reject do |nome|
        t = described_class::V2['etapas'][described_class.normalizar(nome)]
        t && (t['interna'] || (fases.include?(t['fase']) && t['titulo'].present? && t['o_que_esperar'].present?))
      end
      expect(faltando).to eq([])
    end

    it 'etapa desconhecida, vazia ou interna usa o texto padrão (nunca o nome cru)' do
      ['ETAPA NOVA', nil, 'NEGADO / AVISAR CLIENTE'].each do |stage|
        expect(described_class.etapa(stage)['titulo']).to eq 'Em andamento'
      end
      expect(described_class.etapa('Pericia Agendada')['titulo']).to eq 'Perícia marcada'
    end

    it 'flags de e-mail e delicada da tabela' do
      expect(described_class.email?('PERÍCIA AGENDADA')).to be true
      expect(described_class.email?('REUNIÃO PÓS VENDA')).to be false
      expect(described_class.email?('ETAPA NOVA')).to be true
      expect(described_class.etapa('SENTENÇA PROFERIDA')['delicada']).to be true
      expect(described_class.interna?('PRAZO RECURSAL')).to be true
    end

    it 'marcos com os títulos v2, sem marco de concessão' do
      expect(described_class.marcos([{ 'data' => '2026-09-01', 'titulo' => 'Perícia realizada' }]).first['titulo']).to eq 'Perícia'
      expect(described_class.marcos([{ 'data' => '2026-09-01', 'titulo' => 'Benefício concedido' }])).to be_empty
    end

    it 'decisão ainda em análise pela equipe fica em cinza, nunca verde' do
      expect(described_class.status(processo('DECISAO PROFERIDA', 'ADMINISTRATIVO'))).to eq ['analise', 'Em análise']
    end

    it 'fase da etapa; etapa interna ou desconhecida cai no grupo do ADVBOX' do
      expect(described_class.fase_de('IMPROCEDENTE / MONTAR INICIAL', 'ADMINISTRATIVO')).to eq 'justica'
      expect(described_class.fase_de('PRAZO RECURSAL', 'RECURSAL')).to eq 'recurso'
      expect(described_class.fase_de('ETAPA NOVA', 'EXECUÇÃO/COBRANÇA')).to eq 'pagamento'
    end

    it 'linha do tempo no ADMINISTRATIVO: 3 degraus, INSS agora, sem Pagamento prometido' do
      linha = described_class.linha_do_tempo(processo('REQUERIMENTO PROTOCOLADO', 'ADMINISTRATIVO'))
      expect(linha.map { |d| [d['nome'], d['estado']] })
        .to eq([%w[Documentos done], ['Pedido no INSS', 'current'], %w[Concluído future]])
    end

    it 'linha do tempo no RECURSAL: 5 degraus, Recurso agora, sem Pagamento prometido' do
      linha = described_class.linha_do_tempo(processo('RECURSO PROTOCOLADO', 'RECURSAL'))
      expect(linha.pluck('nome')).to eq(['Documentos', 'Pedido no INSS', 'Justiça', 'Recurso', 'Concluído'])
      expect(linha.pluck('estado')).to eq(%w[done done done current future])
    end

    it 'Pagamento só aparece quando o caso está nele' do
      linha = described_class.linha_do_tempo(processo('RPV / PRECATORIO EMITIDO', 'EXECUÇÃO/COBRANÇA'))
      expect(linha.pluck('nome')).to eq(['Documentos', 'Pedido no INSS', 'Justiça', 'Pagamento', 'Concluído'])
      expect(linha.find { |d| d['estado'] == 'current' }['nome']).to eq 'Pagamento'
    end

    it 'linha do tempo segue a etapa exibida ao cliente, não a interna' do
      p = processo('NEGADO / AVISAR CLIENTE', 'JUDICIAL').merge('etapa_cliente' => 'ACAO PROTOCOLADA')
      expect(described_class.linha_do_tempo(p).find { |d| d['estado'] == 'current' }['nome']).to eq 'Justiça'
    end
  end
end
