// Fluxos que substituem automações do código (B4.1, db/seeds/ramon/fluxos/migrados/*.json):
// o quadro abre e publica cada um (validação = espelho do Grafo; a etapa o semear põe) e o desenho é fiel ao código.
import { validar } from '../validar';
import marcada from '../../../../../../../../db/seeds/ramon/fluxos/migrados/reuniao_marcada.json';
import cancelada from '../../../../../../../../db/seeds/ramon/fluxos/migrados/reuniao_cancelada.json';
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
