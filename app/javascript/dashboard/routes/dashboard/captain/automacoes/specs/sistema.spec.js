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
  it('são as 29 automações do código', () => {
    expect(DESENHOS.map(([chave]) => chave).sort()).toEqual([
      'acervo_pecas',
      'agente_hub',
      'assinatura_painel',
      'ata_reuniao',
      'avisos_painel',
      'cadencia',
      'chegada_cliente',
      'coach_objecao',
      'contrato_limpo',
      'contrato_limpo_cancelado',
      'contrato_zapsign',
      'copiloto_noturno',
      'criar_lead_da_conversa',
      'docs_completos',
      'documento_painel',
      'espelho_painel',
      'etiquetas_etapa_tese',
      'eventos_advbox',
      'fechamento_extrato',
      'historico_do_lead',
      'lead_ganho',
      'lembretes_reuniao',
      'origem_do_lead',
      'publicar_pecas',
      'resumo_do_dia',
      'retrato_funil',
      'sdr_automatico',
      'sla_primeira_resposta',
      'sugestao_documento',
    ]);
  });

  it('só Avisos do Painel e Publicar peças saem para fora sem uma pessoa no meio', () => {
    const comSelo = Object.fromEntries(
      DESENHOS.filter(([, d]) => d.alcance).map(([chave, d]) => [
        chave,
        d.alcance,
      ])
    );
    expect(comSelo).toEqual({
      avisos_painel: 'fala_com_cliente',
      publicar_pecas: 'publica',
    });
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
