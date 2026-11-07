// Variação contra o período anterior (regras de design, docs/regras-de-design.md:
// todo número com período e variação). O backend manda o anterior já cortado
// no mesmo ponto (1–18/out × 1–18/nov), então a comparação é justa.

// '%' compara em pontos percentuais; 'n' (contagem pequena: 3 ganhos × 1) em
// diferença absoluta, porque "▲ 200%" engana; o resto em % de mudança.
// sentido 'max' = menor é melhor (1ª resposta, cancelamento): subir é ruim.
export const variacao = (
  atual,
  anterior,
  { unidade, sentido = 'min' } = {}
) => {
  if (atual == null || anterior == null) return null;
  const pontos = unidade === '%';
  const absoluto = unidade === 'n';
  if (!pontos && !absoluto && anterior === 0) return null;
  const delta =
    pontos || absoluto
      ? atual - anterior
      : ((atual - anterior) / anterior) * 100;
  const n = Math.round(Math.abs(delta));
  const extra = absoluto ? { absoluto } : {};
  if (n === 0) return { seta: 'igual', n: 0, pontos, ...extra, tom: 'slate' };
  const sobe = delta > 0;
  return {
    seta: sobe ? 'sobe' : 'desce',
    n,
    pontos,
    ...extra,
    tom: sobe === (sentido !== 'max') ? 'teal' : 'ruby',
  };
};

const FUSO = 'America/Sao_Paulo';
const dia = data =>
  data.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    timeZone: FUSO,
  });
const hora = data =>
  data
    .toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      hour12: false,
      timeZone: FUSO,
    })
    .slice(0, 2);

// { inicio, fim } do backend (fim exclusivo) → chave i18n RAMON.VARIACAO.*:
// "vs 01/10–18/10" ou, num dia só, "vs 17/11 até 14h".
export const rotuloAnterior = periodo => {
  if (!periodo?.inicio || !periodo?.fim) return null;
  const inicio = new Date(periodo.inicio);
  const fim = new Date(periodo.fim);
  const ultimo = new Date(fim.getTime() - 1);
  if (dia(inicio) !== dia(ultimo))
    return { chave: 'VS_DIAS', params: { de: dia(inicio), ate: dia(ultimo) } };
  if (hora(fim) === '00')
    return { chave: 'VS_DIA', params: { dia: dia(inicio) } };
  return { chave: 'VS_ATE', params: { dia: dia(inicio), hora: hora(fim) } };
};
