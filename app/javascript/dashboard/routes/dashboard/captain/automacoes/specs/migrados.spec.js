// Fluxos que substituem automações do código (B4.1, db/seeds/ramon/fluxos/migrados/*.json):
// o quadro abre e publica cada um (validação = espelho do Grafo; a etapa o semear põe) e o desenho é fiel ao código.
import { validar } from '../validar';
import marcada from '../../../../../../../../db/seeds/ramon/fluxos/migrados/reuniao_marcada.json';
import cancelada from '../../../../../../../../db/seeds/ramon/fluxos/migrados/reuniao_cancelada.json';
import sla from '../../../../../../../../db/seeds/ramon/fluxos/migrados/sla_primeira_resposta.json';
import lembretes from '../../../../../../../../db/seeds/ramon/fluxos/migrados/lembretes_reuniao.json';

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
