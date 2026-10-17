import {
  ajustes,
  alternarGatilho,
  estadoDaEtapa,
  efetivo,
  frase,
  marcadorDaPosicao,
  marcadorDe,
  paraGravar,
  permissaoEfetiva,
  posicaoDoMarcador,
  proximaPermissao,
} from '../perfilIa';
import { ETAPAS, PRONTOS, dados } from './perfilIaDados';

const { inicial, gatilhos: CATALOGO } = dados();
const pe = (acao, etapa, cfg) =>
  permissaoEfetiva(acao, etapa, cfg, PRONTOS, ETAPAS);

describe('perfilIa (espelho do Ramon::PerfilIa)', () => {
  it('efetivo: o que falta no cfg vem da base', () => {
    const cfg = { base: 'equilibrada', permissoes: { desqualificar: 's' } };
    const atual = efetivo(cfg, PRONTOS, ETAPAS);
    expect(atual.marcador).toBe('fase-reuniao-agendada');
    expect(atual.permissoes.desqualificar).toBe('s');
    expect(atual.permissoes.citar_honorario).toBe('r');
    expect(atual.gatilhos['fase-novo']).toEqual(PRONTOS.equilibrada.gatilhos);
    expect(efetivo({}, PRONTOS, ETAPAS).base).toBe('cautelosa');
  });

  it('marcador fora da Trilha (etapa apagada) = _inicio', () => {
    expect(marcadorDe({ marcador: 'fase-x' }, PRONTOS, ETAPAS)).toBe('_inicio');
    expect(marcadorDe({ base: 'acelerada' }, PRONTOS, ETAPAS)).toBe('_fim');
  });

  it('ajustes conta ação, Marcador e gatilho diferentes da base', () => {
    expect(ajustes({ base: 'equilibrada' }, PRONTOS, ETAPAS)).toBe(0);
    const cfg = {
      base: 'equilibrada',
      marcador: 'fase-negociacao',
      // pedir_documentos igual à base: não conta
      permissoes: { desqualificar: 's', pedir_documentos: 's' },
      gatilhos: { 'fase-novo': [...PRONTOS.equilibrada.gatilhos, 'nao_le'] },
    };
    expect(ajustes(cfg, PRONTOS, ETAPAS)).toBe(3);
    // padrão inicial: Cautelosa + Marcador no início + 4 ações
    expect(ajustes(inicial, PRONTOS, ETAPAS)).toBe(5);
  });

  it('estadoDaEtapa: até o Marcador sozinha, depois rascunho', () => {
    const m = 'fase-reuniao-agendada';
    expect(estadoDaEtapa('fase-reuniao-agendada', m, ETAPAS)).toBe('sozinha');
    expect(estadoDaEtapa('fase-reuniao-realizada', m, ETAPAS)).toBe('rascunho');
    expect(estadoDaEtapa('fase-novo', '_inicio', ETAPAS)).toBe('rascunho');
    expect(estadoDaEtapa('fase-ultima-chance', '_fim', ETAPAS)).toBe('sozinha');
  });

  it('posição do Marcador vai e volta', () => {
    expect(posicaoDoMarcador('_inicio', ETAPAS)).toBe(0);
    expect(posicaoDoMarcador('fase-qualificacao', ETAPAS)).toBe(2);
    expect(posicaoDoMarcador('_fim', ETAPAS)).toBe(6);
    expect(marcadorDaPosicao(0, ETAPAS)).toBe('_inicio');
    expect(marcadorDaPosicao(2, ETAPAS)).toBe('fase-qualificacao');
    expect(marcadorDaPosicao(6, ETAPAS)).toBe('_fim');
  });

  it('o Marcador é teto: só limita quem está em sozinha depois dele', () => {
    const eq = permissoes => ({ base: 'equilibrada', permissoes });
    expect(pe('contrato_zapsign', 'fase-negociacao', eq())).toMatchObject({
      valor: 'rascunho',
      limitadoPeloMarcador: false,
    });
    expect(
      pe('contrato_zapsign', 'fase-negociacao', eq({ contrato_zapsign: 's' }))
    ).toEqual({
      valor: 'rascunho',
      propria: 'sozinha',
      limitadoPeloMarcador: true,
      liberadoPeloMarcador: false,
    });
    expect(
      pe('contrato_zapsign', 'fase-negociacao', { base: 'acelerada' })
    ).toMatchObject({ valor: 'sozinha', limitadoPeloMarcador: false });
    expect(
      pe('citar_honorario', 'fase-negociacao', { base: 'cautelosa' })
    ).toMatchObject({ valor: 'nunca', limitadoPeloMarcador: false });
  });

  it('fora do horário vale em toda Etapa: o Marcador não o limita', () => {
    expect(pe('fora_do_horario', 'fase-novo', inicial)).toMatchObject({
      valor: 'sozinha',
      propria: 'sozinha',
      limitadoPeloMarcador: false,
    });
  });

  it('logística: antes do Marcador sai sozinha; depois, a própria', () => {
    expect(
      pe('logistica', 'fase-reuniao-agendada', {
        base: 'equilibrada',
        permissoes: { logistica: 'r' },
      })
    ).toEqual({
      valor: 'sozinha',
      propria: 'rascunho',
      limitadoPeloMarcador: false,
      liberadoPeloMarcador: true,
    });
    expect(pe('logistica', 'fase-reuniao-agendada', inicial)).toMatchObject({
      valor: 'sozinha',
      liberadoPeloMarcador: false,
    });
    expect(
      pe('logistica', 'fase-reuniao-agendada', { base: 'cautelosa' })
    ).toMatchObject({ valor: 'rascunho', liberadoPeloMarcador: false });
  });

  it('paraGravar grava o que a tela mostra: Marcador velho = _inicio, sem gatilhos de Etapa velha', () => {
    const cfg = {
      base: 'equilibrada',
      marcador: 'fase-apagada',
      gatilhos: { 'fase-apagada': ['juridica'], 'fase-novo': ['juridica'] },
    };
    expect(marcadorDe(cfg, PRONTOS, ETAPAS)).toBe('_inicio');
    expect(paraGravar(cfg, ETAPAS)).toEqual({
      base: 'equilibrada',
      marcador: '_inicio',
      gatilhos: { 'fase-novo': ['juridica'] },
    });
    expect(paraGravar({ base: 'acelerada' }, ETAPAS)).toEqual({
      base: 'acelerada',
    });
    expect(paraGravar(null, ETAPAS)).toBeNull();
  });

  it('proximaPermissao: S → R → N → S; sem nunca pula o N', () => {
    expect(proximaPermissao('s', false)).toBe('r');
    expect(proximaPermissao('r', false)).toBe('n');
    expect(proximaPermissao('n', false)).toBe('s');
    expect(proximaPermissao('r', true)).toBe('s');
  });

  it('alternarGatilho mantém a ordem do catálogo', () => {
    expect(alternarGatilho(['juridica'], 'pediu_pessoa', CATALOGO)).toEqual([
      'pediu_pessoa',
      'juridica',
    ]);
    expect(
      alternarGatilho(['pediu_pessoa', 'juridica'], 'juridica', CATALOGO)
    ).toEqual(['pediu_pessoa']);
  });

  it('frase do Marcador', () => {
    const t = (chave, p) => (p ? `${chave} ${p.ate} > ${p.depois}` : chave);
    expect(frase('_inicio', ETAPAS, t)).toBe('RAMON.COMO_IA.FRASE.NADA');
    expect(frase('_fim', ETAPAS, t)).toBe('RAMON.COMO_IA.FRASE.TUDO');
    expect(frase('fase-qualificacao', ETAPAS, t)).toBe(
      'RAMON.COMO_IA.FRASE.ATE Qualificação > Reunião agendada'
    );
  });
});
