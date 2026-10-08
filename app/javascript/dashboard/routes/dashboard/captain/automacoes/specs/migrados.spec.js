// Fluxos que substituem automações do código (B4.1, db/seeds/ramon/fluxos/migrados/*.json):
// o quadro abre e publica cada um (validação = espelho do Grafo; a etapa o semear põe) e o desenho é fiel ao código.
import { validar } from '../validar';
import { REGRAS_ADVBOX, ROTINAS, TIPOS_ATIVIDADE, rotinaAlvo } from '../fluxo';
import marcada from '../../../../../../../../db/seeds/ramon/fluxos/migrados/reuniao_marcada.json';
import cancelada from '../../../../../../../../db/seeds/ramon/fluxos/migrados/reuniao_cancelada.json';
import sla from '../../../../../../../../db/seeds/ramon/fluxos/migrados/sla_primeira_resposta.json';
import lembretes from '../../../../../../../../db/seeds/ramon/fluxos/migrados/lembretes_reuniao.json';
import cadencia from '../../../../../../../../db/seeds/ramon/fluxos/migrados/cadencia.json';
import ganho from '../../../../../../../../db/seeds/ramon/fluxos/migrados/lead_ganho.json';
import eventos from '../../../../../../../../db/seeds/ramon/fluxos/migrados/eventos_advbox.json';
import resumoDoDia from '../../../../../../../../db/seeds/ramon/fluxos/migrados/resumo_do_dia.json';
import retratoFunil from '../../../../../../../../db/seeds/ramon/fluxos/migrados/retrato_funil.json';
import fechamentoExtrato from '../../../../../../../../db/seeds/ramon/fluxos/migrados/fechamento_extrato.json';
import espelhoPainel from '../../../../../../../../db/seeds/ramon/fluxos/migrados/espelho_painel.json';
import copilotoNoturno from '../../../../../../../../db/seeds/ramon/fluxos/migrados/copiloto_noturno.json';
import publicarPecas from '../../../../../../../../db/seeds/ramon/fluxos/migrados/publicar_pecas.json';
import avisosPainel from '../../../../../../../../db/seeds/ramon/fluxos/migrados/avisos_painel.json';
import criarLead from '../../../../../../../../db/seeds/ramon/fluxos/migrados/criar_lead_da_conversa.json';
import origemLead from '../../../../../../../../db/seeds/ramon/fluxos/migrados/origem_do_lead.json';
import sugestaoDoc from '../../../../../../../../db/seeds/ramon/fluxos/migrados/sugestao_documento.json';
import coach from '../../../../../../../../db/seeds/ramon/fluxos/migrados/coach_objecao.json';
import agente from '../../../../../../../../db/seeds/ramon/fluxos/migrados/agente_hub.json';
import assinaturaPainel from '../../../../../../../../db/seeds/ramon/fluxos/migrados/assinatura_painel.json';
import contratoAssinado from '../../../../../../../../db/seeds/ramon/fluxos/migrados/contrato_zapsign_assinado.json';
import contratoRecusado from '../../../../../../../../db/seeds/ramon/fluxos/migrados/contrato_zapsign_recusado.json';
import documentoPainel from '../../../../../../../../db/seeds/ramon/fluxos/migrados/documento_painel.json';
import chegada from '../../../../../../../../db/seeds/ramon/fluxos/migrados/chegada_cliente.json';
import ata from '../../../../../../../../db/seeds/ramon/fluxos/migrados/ata_reuniao.json';
import acervoDrive from '../../../../../../../../db/seeds/ramon/fluxos/migrados/acervo_pecas_drive.json';
import acervoNotion from '../../../../../../../../db/seeds/ramon/fluxos/migrados/acervo_pecas_notion.json';

const semEtapa = d =>
  validar(d.desenho).filter(
    e => !(e.codigo === 'FALTA' && e.params.campo === 'etapa_id')
  );
const doTipo = (d, tipo) => d.desenho.nos.filter(n => n.tipo === tipo);
const RASCUNHO =
  '"Oi {primeiro_nome}! Nossa conversa está confirmada pra {quando}. Vou te esperar, tá? Se não puder comparecer, me avise com antecedência que a gente remarca sem problema."';

describe('fluxos migrados: agendamento de reuniões (B4.1)', () => {
  it('os 3 publicam (só falta a etapa, que o semear põe por conta)', () => {
    [marcada, cancelada, lembretes].forEach(d =>
      expect(semEtapa(d)).toEqual([])
    );
    expect(
      [marcada, cancelada, lembretes].map(d => d.desenho.nos[0].config)
    ).toEqual([
      { tipo: 'reuniao_marcada', cancelar_se_sair_da_etapa: false },
      { tipo: 'reuniao_cancelada', cancelar_se_sair_da_etapa: false },
      { tipo: 'reuniao_na_agenda', cancelar_se_sair_da_etapa: false },
    ]);
  });

  it('marcada faz tudo; remarcada só a atividade; os dois juntam no rascunho, sino e push', () => {
    const { setas } = marcada.desenho;
    const de = (id, saida) =>
      setas.find(s => s.de === id && s.saida === saida)?.para;
    expect([
      de('n2', 'c1'),
      de('n3', 's'),
      de('n4', 's'),
      de('n5', 's'),
      de('n6', 's'),
    ]).toEqual(['n3', 'n4', 'n5', 'n6', 'n8']);
    expect([
      de('n2', 'c2'),
      de('n7', 's'),
      de('n8', 's'),
      de('n9', 's'),
    ]).toEqual(['n7', 'n8', 'n9', 'n10']);
    expect(doTipo(marcada, 'criar_tarefa')[0].config).toMatchObject({
      tipo: 'meeting',
      prazo: 'reuniao',
    });
    expect(doTipo(marcada, 'mover_etapa')[0].config.so_para_frente).toBe(true);
    expect(doTipo(marcada, 'trocar_responsavel')[0].config).toMatchObject({
      papel: 'closer',
      so_se_vazio: true,
    });
  });

  it('o rascunho de confirmação é o texto do código, nas notas do lead e com o título do código', () => {
    expect(doTipo(marcada, 'rascunho_texto')[0].config).toMatchObject({
      onde: 'notas_do_lead',
      titulo: 'confirmação de reunião',
      texto: RASCUNHO,
    });
  });

  it('cancelada: atividade, apagar a tarefa, sino e push, nesta ordem', () => {
    expect(cancelada.desenho.nos.map(n => n.tipo)).toEqual([
      'gatilho',
      'registrar_atividade',
      'apagar_reuniao',
      'avisar_sino',
      'avisar_push',
    ]);
  });

  it('lembretes: 24h, 8h, 1h, 30 min e 5 min antes da reunião', () => {
    expect(
      doTipo(lembretes, 'esperar').map(n => [
        n.config.antes_de,
        n.config.quantidade,
        n.config.unidade,
      ])
    ).toEqual([
      ['reuniao', 24, 'horas'],
      ['reuniao', 8, 'horas'],
      ['reuniao', 1, 'horas'],
      ['reuniao', 30, 'minutos'],
      ['reuniao', 5, 'minutos'],
    ]);
  });

  it('lembretes: só com a reunião de pé e no horário, para o Closer e o SDR; o "não" pula para o próximo', () => {
    doTipo(lembretes, 'se').forEach(n =>
      expect(n.config.condicoes).toEqual([
        { campo: 'reuniao_de_pe', operador: 'igual', valor: 'sim' },
        { campo: 'horario_passou', operador: 'igual', valor: 'nao' },
      ])
    );
    doTipo(lembretes, 'avisar_sino').forEach(n =>
      expect(n.config.para).toBe('closer_e_sdr')
    );
    const esperas = doTipo(lembretes, 'esperar').map(n => n.id);
    const naos = lembretes.desenho.setas
      .filter(s => s.saida === 'nao')
      .map(s => s.para);
    expect(naos).toEqual(esperas.slice(1));
  });

  it('nenhum dos 3 fala com o cliente: o único texto ao cliente é o rascunho', () => {
    const tipos = [marcada, cancelada, lembretes].flatMap(d =>
      d.desenho.nos.map(n => n.tipo)
    );
    expect([...new Set(tipos)].sort()).toEqual([
      'apagar_reuniao',
      'avisar_push',
      'avisar_sino',
      'criar_tarefa',
      'escolha',
      'esperar',
      'gatilho',
      'mover_etapa',
      'rascunho_texto',
      'registrar_atividade',
      'se',
      'trocar_responsavel',
    ]);
  });
});

describe('fluxo migrado: SLA da 1ª resposta (B4.2)', () => {
  const de = (id, saida) =>
    sla.desenho.setas.find(s => s.de === id && s.saida === saida)?.para;
  const VIVA = [
    { campo: 'primeira_resposta', operador: 'igual', valor: 'nao' },
    { campo: 'status', operador: 'igual', valor: 'open' },
    { campo: 'etapa', operador: 'existe', valor: '' },
  ];
  const HORARIO = {
    campo: 'status',
    operador: 'em_horario_comercial',
    valor: '',
    dias: [0, 1, 2, 3, 4, 5, 6],
    inicio: 7,
    fim: 21,
  };

  it('publica, nasce da conversa nova e não cancela por etapa', () => {
    expect(validar(sla.desenho)).toEqual([]);
    expect(sla.desenho.nos[0].config).toEqual({
      tipo: 'conversa_criada',
      cancelar_se_sair_da_etapa: false,
    });
  });

  it('espera o SLA da caixa; depois até 60 min da criação da conversa', () => {
    expect(doTipo(sla, 'esperar').map(n => n.config)).toEqual([
      { rotulo: 'SLA da caixa', desde: 'conversa', prazo: 'sla_caixa' },
      {
        rotulo: 'Até 60 min da criação da conversa',
        desde: 'conversa',
        quantidade: 60,
        unidade: 'minutos',
      },
    ]);
  });

  it('as guardas do código, a escalada só se ainda vale, e a janela 7h–21h todo dia', () => {
    const [primeiro, horario1, segundo, horario2] = doTipo(sla, 'se').map(
      n => n.config.condicoes
    );
    expect(primeiro).toEqual(VIVA);
    expect(segundo).toEqual([
      { campo: 'horario_passou', operador: 'igual', valor: 'nao' },
      ...VIVA,
    ]);
    expect([horario1, horario2]).toEqual([[HORARIO], [HORARIO]]);
  });

  it('fora do horário pula o aviso, mas segue para a escalada', () => {
    expect([de('n4', 'sim'), de('n4', 'nao'), de('n6', 's')]).toEqual([
      'n5',
      'n7',
      'n7',
    ]);
  });

  it('SDR (sem SDR: gestores) com push; a escalada só os gestores, sem push', () => {
    expect(doTipo(sla, 'avisar_sino').map(n => n.config.para)).toEqual([
      'sdr_ou_gestores',
      'gestores',
    ]);
    expect(doTipo(sla, 'avisar_push').map(n => n.config.titulo)).toEqual([
      'Lead aguardando 1a resposta',
    ]);
  });
});

describe('fluxo migrado: cadência de retomada (B4.3)', () => {
  const RESERVA =
    'Oi {nome}, tudo bem? Passando pra saber se você ainda tem interesse em olhar o seu caso com a gente. Qualquer coisa, estou por aqui!';

  it('publica sem erro; gatilho Lead parado com retomada às 11h', () => {
    expect(validar(cadencia.desenho)).toEqual([]);
    expect(cadencia.desenho.nos[0].config).toEqual({
      tipo: 'lead_parado',
      hora: '11:00',
      retomada: true,
    });
  });

  it('rascunho da IA nas notas (título com o nº, reserva = texto fixo do código), conta, tarefa de hoje, push 1 por dia', () => {
    expect(cadencia.desenho.nos.map(n => n.tipo)).toEqual([
      'gatilho',
      'rascunho_ia',
      'registrar_retomada',
      'criar_tarefa',
      'avisar_push',
    ]);
    expect(doTipo(cadencia, 'rascunho_ia')[0].config).toMatchObject({
      onde: 'notas_do_lead',
      titulo: 'retomada nº {tentativa}',
      reserva: RESERVA,
    });
    expect(doTipo(cadencia, 'criar_tarefa')[0].config).toMatchObject({
      titulo: 'Retomada nº {tentativa}',
      tipo: 'follow_up',
      prazo_dias: 0,
    });
    expect(doTipo(cadencia, 'avisar_push')[0].config.uma_vez_por_dia).toBe(
      true
    );
  });
});

// = Ramon::AdvboxEventRegras (o texto do código, com as aspas e a quebra de linha)
const RASCUNHOS_ADVBOX = {
  'INSS negou':
    '"Oi {primeiro_nome}, tudo bem? Saiu a decisão do INSS sobre o seu pedido e, infelizmente, foi negativa.\nIsso não é o fim: muitos casos como o seu são revertidos na Justiça. Posso te explicar os próximos passos?"',
  'exigência do INSS':
    '"Oi {primeiro_nome}! O INSS pediu um documento a mais no seu processo. Pode me mandar por aqui quando conseguir? Te ajudo com o que precisar."',
  'comunicado de êxito':
    '"{primeiro_nome}, ótima notícia! 🎉 Saiu o pagamento do seu processo. Foi uma alegria acompanhar seu caso até aqui.\nSe puder, sua avaliação no Google ajuda muito outras pessoas a nos encontrarem."',
  'benefício concedido':
    '"{primeiro_nome}, notícia boa! 🎉 O INSS CONCEDEU o seu benefício. Agora vamos conferir a implantação e os valores — te aviso de cada passo."',
};

describe('fluxos migrados: lead ganho e eventos do ADVBOX (B4.4/B4.5)', () => {
  it('os 2 publicam (só falta a etapa de ganho, que o semear põe)', () => {
    [ganho, eventos].forEach(d => expect(semEtapa(d)).toEqual([]));
    expect([ganho, eventos].map(d => d.desenho.nos[0].config)).toEqual([
      { tipo: 'lead_ganho', cancelar_se_sair_da_etapa: false },
      { tipo: 'evento_advbox', cancelar_se_sair_da_etapa: false },
    ]);
  });

  it('lead ganho: dossiê → NPS → ADVBOX por último (fora do ar não segura o resto); o Drive fica no código', () => {
    expect(ganho.desenho.nos.slice(1).map(n => n.config.rotina)).toEqual([
      'dossie_passagem',
      'pesquisa_nps',
      'abrir_caso_advbox',
    ]);
  });

  it('eventos: os 4 rascunhos ao cliente são o texto do código, nas notas do lead e com o título do código', () => {
    const rascunhos = Object.fromEntries(
      doTipo(eventos, 'rascunho_texto').map(n => [n.config.titulo, n.config])
    );
    Object.entries(RASCUNHOS_ADVBOX).forEach(([titulo, texto]) =>
      expect(rascunhos[titulo]).toMatchObject({ onde: 'notas_do_lead', texto })
    );
    expect(Object.keys(rascunhos)).toHaveLength(4);
  });

  it('eventos: uma saída por regra, cada uma com a atividade do código; contrato fechado só marca ganho', () => {
    const casos = eventos.desenho.nos[1].config.casos.map(c => c.valores[0]);
    expect(casos).toEqual(REGRAS_ADVBOX);
    expect(
      doTipo(eventos, 'registrar_atividade').map(n => n.config.tipo)
    ).toEqual(TIPOS_ATIVIDADE.filter(k => k.startsWith('advbox_')));
    const { setas } = eventos.desenho;
    const de = id => setas.find(s => s.de === id)?.para;
    expect([de('n3'), de('n4'), de('n5')]).toEqual(['n4', 'n5', undefined]);
  });

  it('eventos: êxito e concessão pedem a NPS de êxito; arquivado conclui as tarefas antes da atividade', () => {
    expect(doTipo(eventos, 'rotina').map(n => [n.id, n.config.rotina])).toEqual(
      [
        ['n24', 'pesquisa_nps_exito'],
        ['n30', 'pesquisa_nps_exito'],
        ['n32', 'concluir_tarefas'],
      ]
    );
    expect(eventos.desenho.setas.find(s => s.de === 'n32').para).toBe('n33');
  });

  it('nenhum dos 2 fala com o cliente: o único texto ao cliente é rascunho (e a NPS, que é rascunho)', () => {
    const tipos = [ganho, eventos].flatMap(d => d.desenho.nos.map(n => n.tipo));
    expect([...new Set(tipos)].sort()).toEqual([
      'avisar_push',
      'criar_tarefa',
      'escolha',
      'gatilho',
      'mover_etapa',
      'rascunho_texto',
      'registrar_atividade',
      'rotina',
    ]);
  });
});

const CONTA = {
  resumo_do_dia: resumoDoDia,
  retrato_funil: retratoFunil,
  fechamento_extrato: fechamentoExtrato,
  espelho_painel: espelhoPainel,
  copiloto_noturno: copilotoNoturno,
  publicar_pecas: publicarPecas,
  avisos_painel: avisosPainel,
};

describe('fluxos migrados: rotinas da conta (B5-conta)', () => {
  it.each(Object.entries(CONTA))(
    '%s: publica, no Horário da conta, com a rotina de mesmo nome',
    (chave, d) => {
      expect(validar(d.desenho)).toEqual([]);
      expect(d.desenho.nos.map(n => n.tipo)).toEqual(['gatilho', 'rotina']);
      expect(d.desenho.nos[0].config.tipo).toBe('horario_conta');
      expect(d.desenho.nos[1].config.rotina).toBe(chave);
      expect(rotinaAlvo(chave)).toBe('conta');
    }
  );

  it('no horário de hoje do código (config/schedule.yml, em São Paulo)', () => {
    const quandoRoda = Object.fromEntries(
      Object.entries(CONTA).map(([k, d]) => {
        const c = d.desenho.nos[0].config;
        return [k, c.hora || `${c.a_cada_minutos} min`];
      })
    );
    expect(quandoRoda).toEqual({
      resumo_do_dia: '08:00',
      retrato_funil: '00:05',
      fechamento_extrato: '00:20',
      espelho_painel: '00:30',
      copiloto_noturno: '05:00',
      publicar_pecas: '1 min',
      avisos_painel: '08:00',
    });
  });
});

describe('fluxos migrados: leads e conversas (B5-leads)', () => {
  it.each([
    ['criar lead', criarLead, 'conversa_criada', 'criar_lead'],
    ['origem', origemLead, 'mensagem_recebida', 'origem_do_lead'],
    ['documento', sugestaoDoc, 'mensagem_recebida', 'sugestao_documento'],
    ['coach', coach, 'mensagem_recebida', 'coach_objecao'],
    ['agente', agente, 'nota_escrita', 'agente_hub'],
  ])(
    '%s: publica; gatilho certo sem cancelar por etapa; 1 rotina pronta do hub',
    (_nome, d, gatilho, rotina) => {
      expect(validar(d.desenho)).toEqual([]);
      expect(d.desenho.nos[0].config).toEqual({
        tipo: gatilho,
        cancelar_se_sair_da_etapa: false,
      });
      expect(d.desenho.nos.map(n => n.tipo)).toEqual(['gatilho', 'rotina']);
      expect(d.desenho.nos[1].config.rotina).toBe(rotina);
      expect(ROTINAS).toContain(rotina);
      expect(rotinaAlvo(rotina)).toBe('conversa');
    }
  );
});

// = a ordem do semear dos 8 desenhos B5-externos
const EXTERNOS = [
  assinaturaPainel,
  contratoAssinado,
  contratoRecusado,
  documentoPainel,
  chegada,
  ata,
  acervoDrive,
  acervoNotion,
];

describe('fluxos migrados: automações de fora do funil (B5-externos)', () => {
  it('os 8 publicam, cada um com o seu gatilho e sem cancelar por etapa', () => {
    EXTERNOS.forEach(d => expect(validar(d.desenho)).toEqual([]));
    expect(EXTERNOS.map(d => d.desenho.nos[0].config.tipo)).toEqual([
      'assinatura_painel',
      'contrato_assinado',
      'contrato_recusado',
      'documento_painel',
      'chegada_cliente',
      'reuniao_gravada',
      'peca_publicada',
      'peca_mudou_status',
    ]);
    EXTERNOS.forEach(d =>
      expect(d.desenho.nos[0].config.cancelar_se_sair_da_etapa).toBe(false)
    );
  });

  it('cada um chama a rotina pronta de hoje; só a chegada espera (3 minutos) antes', () => {
    const rotinas = EXTERNOS.map(d =>
      doTipo(d, 'rotina').map(n => n.config.rotina)
    );
    expect(rotinas).toEqual([
      ['conferir_assinatura_painel'],
      ['aviso_contrato'],
      ['aviso_contrato'],
      ['processar_envio_painel'],
      ['escalar_chegada'],
      ['escrever_ata'],
      ['acervo_drive'],
      ['espelho_notion'],
    ]);
    rotinas.flat().forEach(r => expect(rotinaAlvo(r)).toBeDefined());
    expect(ROTINAS).toEqual(expect.arrayContaining(rotinas.flat()));
    expect(chegada.desenho.nos.map(n => n.tipo)).toEqual([
      'gatilho',
      'esperar',
      'rotina',
    ]);
    expect(doTipo(chegada, 'esperar')[0].config).toMatchObject({
      quantidade: 3,
      unidade: 'minutos',
    });
  });

  it('nenhum fala com o cliente: só gatilho, espera e rotina pronta', () => {
    const tipos = EXTERNOS.flatMap(d => d.desenho.nos.map(n => n.tipo));
    expect([...new Set(tipos)].sort()).toEqual([
      'esperar',
      'gatilho',
      'rotina',
    ]);
  });
});
