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
      expect(d.resumo.length).toBeGreaterThan(0);
      expect(d.resumo.length).toBeLessThanOrEqual(120);
      expect(d.resumo).not.toMatch(/::|#|No código/);
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

  it('nenhum desenho manda mensagem direto ao cliente (só rascunho, nota e aviso)', () => {
    const ENVIOS = ['send_message', 'send_attachment', 'send_email_transcript'];
    const CONHECIDOS = [
      'acao_chatwoot',
      'advbox',
      'avisar_push',
      'avisar_sino',
      'criar_tarefa',
      'escolha',
      'esperar',
      'gatilho',
      'mover_etapa',
      'nota_privada',
      'perguntar_ia',
      'preencher_campo',
      'rascunho_ia',
      'rascunho_texto',
      'registrar_atividade',
      'se',
      'trocar_responsavel',
      'webhook', // agente_hub (interno) e publicar_pecas (Instagram, selo publica)
    ];
    const nos = DESENHOS.flatMap(([, d]) => d.desenho.nos);
    const envios = nos
      .filter(n => n.tipo === 'acao_chatwoot')
      .flatMap(n => n.config.acoes.map(a => a.action_name))
      .filter(a => ENVIOS.includes(a));
    expect(envios).toEqual([]);
    expect(nos.map(n => n.tipo).filter(t => !CONHECIDOS.includes(t))).toEqual(
      []
    );
  });

  it('o ciclo de lembretes de reunião não fixa "24h" no título do push', () => {
    const d = Object.fromEntries(DESENHOS).lembretes_reuniao;
    const titulos = d.desenho.nos
      .filter(n => n.tipo === 'avisar_push')
      .map(n => n.config.titulo);
    expect(titulos.length).toBeGreaterThan(0);
    titulos.forEach(t => expect(t).not.toMatch(/24h/));
  });

  it('as 5 regras de dado e as etiquetas são regra fixa (decisão do Eduardo 07/10)', () => {
    expect(
      DESENHOS.filter(([, d]) => d.fixa)
        .map(([chave]) => chave)
        .sort()
    ).toEqual([
      'contrato_limpo',
      'contrato_limpo_cancelado',
      'docs_completos',
      'etiquetas_etapa_tese',
      'historico_do_lead',
      'sdr_automatico',
    ]);
    DESENHOS.forEach(([, d]) => expect([undefined, true]).toContain(d.fixa));
  });
});
