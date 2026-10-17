// Espelho do Ramon::PerfilIa (app/services/ramon/perfil_ia.rb) para a tela "Como a IA atende".
// cfg = { base, marcador, permissoes { acao => s|r|n }, gatilhos { etapa => [chaves] } }; o que falta vem da base.
// prontos/etapas = os do GET ramon_ia_atendimento.
import { TOM } from './ui';

export const INICIO = '_inicio';
export const FIM = '_fim';
export const PERMISSAO = { s: 'sozinha', r: 'rascunho', n: 'nunca' };
// Cores da tela: barra cheia (trilha) e etiqueta translúcida (estado/permissão).
export const COR_DO_ESTADO = {
  sozinha: 'bg-n-teal-9',
  rascunho: 'bg-n-amber-9',
};
export const TOM_DO_ESTADO = {
  sozinha: TOM.teal,
  rascunho: TOM.amber,
  nunca: TOM.ruby,
};
// Logística é justamente o que sai sozinho depois do Marcador (logistica_sai?): o Marcador não a limita.
const SEM_TETO = ['logistica'];

export const baseDe = cfg => cfg.base || 'cautelosa';

// Chave de Etapa, _inicio ou _fim; o que não está na Trilha (etapa apagada) = _inicio.
export const marcadorDe = (cfg, prontos, etapas) => {
  const valor = cfg.marcador || prontos[baseDe(cfg)].marcador;
  return [INICIO, FIM, ...etapas.map(e => e.chave)].includes(valor)
    ? valor
    : INICIO;
};

// Posição do Marcador na Trilha: 0 = antes de todas … etapas.length = depois de todas.
export const posicaoDoMarcador = (marcador, etapas) =>
  marcador === FIM
    ? etapas.length
    : etapas.findIndex(e => e.chave === marcador) + 1;

export const marcadorDaPosicao = (posicao, etapas) => {
  if (posicao <= 0) return INICIO;
  if (posicao >= etapas.length) return FIM;
  return etapas[posicao - 1].chave;
};

export const estadoDaEtapa = (chave, marcador, etapas) =>
  etapas.findIndex(e => e.chave === chave) < posicaoDoMarcador(marcador, etapas)
    ? 'sozinha'
    : 'rascunho';

// O que a IA faria com este cfg: base, Marcador válido, Permissão de cada ação e Gatilhos de cada Etapa.
export const efetivo = (cfg, prontos, etapas) => {
  const base = baseDe(cfg);
  const pronto = prontos[base];
  return {
    base,
    marcador: marcadorDe(cfg, prontos, etapas),
    permissoes: Object.fromEntries(
      Object.keys(pronto.permissoes).map(acao => [
        acao,
        cfg.permissoes?.[acao] ?? pronto.permissoes[acao],
      ])
    ),
    gatilhos: Object.fromEntries(
      etapas.map(e => [e.chave, cfg.gatilhos?.[e.chave] ?? pronto.gatilhos])
    ),
  };
};

const diferenca = (a, b) =>
  a.filter(x => !b.includes(x)).length + b.filter(x => !a.includes(x)).length;

// Quantos ajustes à mão sobre a base: Marcador (1), cada ação e cada Gatilho de cada Etapa diferentes.
export const ajustes = (cfg, prontos, etapas) => {
  const atual = efetivo(cfg, prontos, etapas);
  const pronto = prontos[atual.base];
  const acoes = Object.keys(atual.permissoes).filter(
    acao => atual.permissoes[acao] !== pronto.permissoes[acao]
  ).length;
  const gatilhos = etapas.reduce(
    (n, e) => n + diferenca(atual.gatilhos[e.chave], pronto.gatilhos),
    0
  );
  return (atual.marcador === pronto.marcador ? 0 : 1) + acoes + gatilhos;
};

// O Marcador é teto: depois dele, sozinha vira rascunho (nunca continua nunca).
export const permissaoEfetiva = (acao, etapa, cfg, prontos, etapas) => {
  const propria = PERMISSAO[efetivo(cfg, prontos, etapas).permissoes[acao]];
  const limitadoPeloMarcador =
    !SEM_TETO.includes(acao) &&
    propria !== 'nunca' &&
    estadoDaEtapa(etapa, marcadorDe(cfg, prontos, etapas), etapas) ===
      'rascunho';
  return {
    valor: limitadoPeloMarcador ? 'rascunho' : propria,
    propria,
    limitadoPeloMarcador,
  };
};

// Sozinha → Rascunho → Nunca → Sozinha; ação sem "nunca" volta de Rascunho para Sozinha.
export const proximaPermissao = (valor, semNunca) => {
  if (valor === 's') return 'r';
  if (valor === 'r') return semNunca ? 's' : 'n';
  return 's';
};

// Liga/desliga um Gatilho, mantendo a ordem do catálogo (a mesma do servidor).
export const alternarGatilho = (lista, chave, catalogo) =>
  catalogo
    .map(g => g.chave)
    .filter(c => (c === chave ? !lista.includes(c) : lista.includes(c)));

export const frase = (marcador, etapas, t) => {
  const posicao = posicaoDoMarcador(marcador, etapas);
  if (posicao === 0) return t('RAMON.COMO_IA.FRASE.NADA');
  if (posicao === etapas.length) return t('RAMON.COMO_IA.FRASE.TUDO');
  return t('RAMON.COMO_IA.FRASE.ATE', {
    ate: etapas[posicao - 1].nome,
    depois: etapas[posicao].nome,
  });
};
