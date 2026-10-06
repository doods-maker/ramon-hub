// Trava dos desenhos do sistema (db/seeds/ramon/fluxos/sistema/*.json, spec §8 +
// decisão do Eduardo 06/10: as 29 automações do código): o quadro abre cada um e a
// validação (espelho do Grafo) só deixa passar a etapa em aberto — a etapa é do
// funil de cada conta e a B4 escolhe ao migrar.
import { ALCANCES, GRUPOS_SISTEMA } from '../fluxo';
import { validar } from '../validar';

const ARQUIVOS = import.meta.glob(
  '../../../../../../../../db/seeds/ramon/fluxos/sistema/*.json',
  { eager: true, import: 'default' }
);
const DESENHOS = Object.entries(ARQUIVOS).map(([caminho, d]) => [
  caminho.split('/').pop().replace('.json', ''),
  d,
]);

describe('fluxos do sistema', () => {
  it('tem os 6 da spec §8', () => {
    expect(DESENHOS.map(([chave]) => chave)).toEqual(
      expect.arrayContaining([
        'cadencia',
        'eventos_advbox',
        'lead_ganho',
        'lembretes_reuniao',
        'resumo_do_dia',
        'sla_primeira_resposta',
      ])
    );
  });

  it.each(DESENHOS)(
    '%s: nome, grupo, onde vive no código e desenho válido (menos a etapa)',
    (_chave, d) => {
      expect(d.nome).toBeTruthy();
      expect(GRUPOS_SISTEMA).toContain(d.grupo);
      expect([undefined, ...ALCANCES]).toContain(d.alcance);
      expect(d.descricao.split('\n')[0]).toMatch(/^No código: /);
      const erros = validar(d.desenho).filter(
        e => !(e.codigo === 'FALTA' && e.params.campo === 'etapa_id')
      );
      expect(erros).toEqual([]);
    }
  );

  it.each(DESENHOS)(
    '%s: todo passo diz no rótulo o que o código faz',
    (_chave, d) => {
      const semRotulo = d.desenho.nos
        .filter(n => n.tipo !== 'gatilho' && !n.config?.rotulo)
        .map(n => n.id);
      expect(semRotulo).toEqual([]);
    }
  );
});
