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

  it 'encerrado: equipe arquivou (ARQUIVAMENTO) ou o tribunal deu baixa definitiva' do
    expect(described_class.encerrado?({ 'fase' => 'ARQUIVAMENTO' })).to be true
    expect(described_class.encerrado?({ 'fase' => 'RH/FINANCEIRO' })).to be false
    expect(described_class.encerrado?({ 'fase' => 'JUDICIAL', 'etapa_cliente' => 'ARQUIVADO/ENCERRADO' })).to be true
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

    # Títulos reais do ADVBOX (TRF4/TJSC) dos casos que o Eduardo achou errados em 08/10.
    def andamento(data, titulo) = { 'data' => data, 'titulo' => titulo }

    it 'tribunal: cumprimento de sentença contra a Fazenda vira Pagamento, mesmo com sentença no mesmo dia' do
      andamentos = [
        andamento('2026-06-10', 'Expedida/certificada a intimação eletrônica - Acordo Homologado (EXEQUENTE - SIEMES ELISEU LINS) Prazo: 5 dias'),
        andamento('2026-06-10', 'Classe Processual alterada - DE: PROCEDIMENTO COMUM PARA: Cumprimento de Sentença contra a Fazenda Pública'),
        andamento('2026-09-09', 'Expedida/certificada a intimação eletrônica (EXEQUENTE - SIEMES ELISEU LINS) Prazo: 5 dias')
      ]
      expect(described_class.achado_do_tribunal(andamentos)).to eq('etapa' => 'EXECUCAO COMO EXEQUENTE', 'data' => '2026-06-10',
                                                                   'titulo' => andamentos[1]['titulo'])
    end

    it 'tribunal: baixa definitiva encerra; recurso julgado vence a sentença de antes' do
      expect(described_class.achado_do_tribunal([andamento('2025-09-25', 'Baixa Definitiva')])['etapa']).to eq 'ARQUIVADO/ENCERRADO'
      andamentos = [andamento('2026-07-15', 'Julgado improcedente o pedido'),
                    andamento('2026-08-27', 'Remetidos os Autos em grau de recurso para TR - Órgão Julgador: SCFLPTR02B'),
                    andamento('2026-09-25', 'Sentença confirmada - por unanimidade')]
      expect(described_class.achado_do_tribunal(andamentos.first(2))['etapa']).to eq 'AGUARDANDO JULGAMENTO DO RECURSO'
      expect(described_class.achado_do_tribunal(andamentos)['etapa']).to eq 'RECURSO JULGADO'
    end

    it 'tribunal: andamento comum não muda nada e o achado do espelho anterior fica' do
      comuns = [andamento('2026-09-23', 'Conclusos para decisão'), andamento('2026-08-30', 'PETIÇÃO - Refer. aos Eventos: 604, 605'),
                andamento('2026-07-10', 'Juntada de Petição - EXECUÇÃO/CUMPRIMENTO DE SENTENÇA'),
                andamento('2026-07-08', 'Expedida/certificada a intimação eletrônica - Requisição - Cumprimento - Implantar Benefício')]
      expect(described_class.achado_do_tribunal(comuns)).to be_nil
      anterior = { 'etapa' => 'EXECUCAO COMO EXEQUENTE', 'data' => '2026-06-10',
                   'titulo' => 'Classe alterada para Cumprimento de Sentença contra a Fazenda' }
      expect(described_class.achado_do_tribunal(comuns, anterior)).to eq anterior
    end

    it 'tribunal: "conclusos para sentença" e "audiência não realizada" não mudam a fase nem viram marco' do
      ['Conclusos para sentença', 'Audiência de instrução não realizada', 'Intimação para manifestação sobre laudo pericial',
       'Baixa Definitiva - Declinada Competência - Processo distribuído. Local', 'Conclusos os autos para julgamento Proferir sentença',
       'Extinta a execução ou o cumprimento da sentença - tipo B', 'Requisição de Pequeno Valor cancelada'].each do |t|
        expect(described_class.achado_do_tribunal([andamento('2026-10-01', t)])).to be_nil
      end
      expect(described_class.marcos([andamento('2026-10-01', 'Conclusos para sentença')])).to be_empty
    end

    it 'tribunal: no pagamento, sentença ou acórdão depois não devolve a fase; RPV e baixa avançam' do
      cumprimento = andamento('2026-06-10', 'Classe Processual alterada - PARA: Cumprimento de Sentença contra a Fazenda Pública')
      depois = [andamento('2026-08-01', 'Expedida/certificada a intimação eletrônica - Sentença (EXEQUENTE - FULANO)'),
                andamento('2026-08-05', 'Juntada de Relatório/Voto/Acórdão')]
      expect(described_class.achado_do_tribunal([cumprimento] + depois)['etapa']).to eq 'EXECUCAO COMO EXEQUENTE'
      rpv = andamento('2026-09-01', 'Expedida Requisição de Pequeno Valor - RPV')
      expect(described_class.achado_do_tribunal([cumprimento, rpv] + depois)['etapa']).to eq 'RPV / PRECATORIO EMITIDO'
      expect(described_class.achado_do_tribunal([cumprimento, andamento('2026-10-01', 'Baixa Definitiva')])['etapa']).to eq 'ARQUIVADO/ENCERRADO'
    end

    it 'tribunal: impugnação do INSS ao cálculo é cobrança (não ordem de pagamento); arquivamento definitivo do TJ encerra' do
      impugnacao = 'Expedida/certificada a intimação eletrônica - Impugnação (art. 535, CPC) - Precatório (EXEQUENTE - X) Prazo: 15 dias'
      expect(described_class.achado_do_tribunal([andamento('2026-09-01', impugnacao)])['etapa']).to eq 'EXECUCAO COMO EXEQUENTE'
      tj = "Arquivamento\nData de arquivamento: 01/02/2026\nTipo de arquivamento: Definitivo"
      expect(described_class.achado_do_tribunal([andamento('2026-02-01', tj)])['etapa']).to eq 'ARQUIVADO/ENCERRADO'
      expect(described_class.achado_do_tribunal([andamento('2026-02-01', tj.sub('Definitivo', 'Provisório'))])).to be_nil
    end

    it 'tribunal: achado gravado com regra antiga é reavaliado pelo título (corrigir o YAML corrige o espelho)' do
      errado = { 'etapa' => 'SENTENCA PROFERIDA', 'data' => '2026-09-01', 'titulo' => 'Conclusos para sentença' }
      expect(described_class.achado_do_tribunal([], errado)).to be_nil
      expect(described_class.achado_do_tribunal([], errado.except('titulo'))).to be_nil
    end

    it 'etapa real: baixa definitiva com andamento depois (autos voltaram à origem) não encerra' do
      p = { 'etapa' => 'X', 'fase' => 'JUDICIAL', 'numero' => '5000384-66.2024.4.04.7216',
            'tribunal' => { 'etapa' => 'ARQUIVADO/ENCERRADO', 'data' => '2025-09-25' },
            'andamentos' => [andamento('2025-10-02', 'Recebidos os autos'), andamento('2025-09-25', 'Baixa Definitiva')] }
      expect(described_class.etapa_real(p)).to eq 'ACAO PROTOCOLADA'
      expect(described_class.etapa_real(p.merge('andamentos' => p['andamentos'].last(1)))).to eq 'ARQUIVADO/ENCERRADO'
    end

    it 'marco Decisão não dispara com "Cumprimento de Sentença"' do
      titulo = 'Classe Processual alterada - DE: PROCEDIMENTO COMUM PARA: Cumprimento de Sentença contra a Fazenda Pública'
      expect(described_class.marcos([andamento('2026-06-10', titulo)])).to be_empty
    end

    it 'etapa real ignora a coluna do ADVBOX: agenda > tribunal > nº CNJ > protocolo INSS' do
      ademir = { 'etapa' => 'FASE DE INSTRUÇÃO', 'fase' => 'JUDICIAL', 'numero' => '0000498-04.2012.8.24.0044',
                 'agenda' => [{ 'tipo' => 'audiencia', 'quando' => '2027-03-09 16:00:00', 'formato' => 'presencial' }] }
      expect(described_class.etapa_real(ademir)).to eq 'PAINEL AUDIENCIA MARCADA'
      expect(described_class.etapa(described_class.etapa_real(ademir))['titulo']).to eq 'Audiência marcada'
      expect(described_class.etapa_real(ademir.except('agenda'))).to eq 'ACAO PROTOCOLADA'

      siemes = { 'etapa' => 'SENTENÇA PROFERIDA', 'fase' => 'JUDICIAL', 'numero' => '5000939-49.2025.4.04.7216',
                 'tribunal' => { 'etapa' => 'EXECUCAO COMO EXEQUENTE', 'data' => '2026-06-10' } }
      expect(described_class.etapa_real(siemes)).to eq 'EXECUCAO COMO EXEQUENTE'

      inss = { 'etapa' => 'PERICIA AGENDADA', 'fase' => 'ADMINISTRATIVO', 'numero' => nil, 'protocolo' => '547629991' }
      expect(described_class.etapa_real(inss)).to eq 'REQUERIMENTO PROTOCOLADO'
      expect(described_class.etapa_real(inss.merge('agenda' => [{ 'tipo' => 'pericia', 'quando' => '2026-11-03 09:00:00' }])))
        .to eq 'PERICIA AGENDADA'
    end

    it 'etapa real: benefício concedido marcado pela equipe vale (selo verde)' do
      concedido = { 'etapa' => 'BENEFÍCIO CONCEDIDO / IMPLANTAÇÃO', 'fase' => 'ADMINISTRATIVO', 'numero' => nil, 'protocolo' => '547629991' }
      expect(described_class.etapa_real(concedido)).to eq 'BENEFÍCIO CONCEDIDO / IMPLANTAÇÃO'
      expect(described_class.status(concedido.merge('etapa_cliente' => described_class.etapa_real(concedido)))).to eq %w[aprovado Aprovado]
    end

    it 'etapa real: baixa no tribunal encerra; arquivado pela equipe mostra o motivo' do
      baixa = { 'etapa' => 'FASE DE INSTRUÇÃO', 'fase' => 'JUDICIAL', 'numero' => '5000384-66.2024.4.04.7216',
                'tribunal' => { 'etapa' => 'ARQUIVADO/ENCERRADO', 'data' => '2025-09-25' } }
      expect(described_class.etapa_real(baixa)).to eq 'ARQUIVADO/ENCERRADO'
      equipe = { 'etapa' => 'ANALISADO E NÃO DISTRIBUÍDO', 'fase' => 'ARQUIVAMENTO', 'numero' => '5006509-72.2013.4.04.7204' }
      expect(described_class.etapa_real(equipe)).to eq 'ANALISADO E NÃO DISTRIBUÍDO'
    end

    it 'linha do tempo do cumprimento de sentença: passou pela Justiça e está no Pagamento' do
      p = processo('SENTENÇA PROFERIDA', 'JUDICIAL').merge('numero' => '5000939-49.2025.4.04.7216', 'etapa_cliente' => 'EXECUCAO COMO EXEQUENTE')
      linha = described_class.linha_do_tempo(p)
      expect(linha.pluck('nome')).to eq(['Documentos', 'Pedido no INSS', 'Justiça', 'Pagamento', 'Concluído'])
      expect(linha.find { |d| d['estado'] == 'current' }['nome']).to eq 'Pagamento'
    end
  end
end
