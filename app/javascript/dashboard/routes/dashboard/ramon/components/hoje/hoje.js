// Peças comuns das telas Hoje (mockup v2 .lin/.btn/.caixa) + formato de tempo.
const ZONA = 'America/Sao_Paulo';

export const GRADE =
  'grid w-full max-w-[1240px] grid-cols-1 gap-10 px-7 pb-12 pt-6 xl:grid-cols-[1fr_300px]';
export const LINHA =
  'flex items-center gap-3.5 border-b border-n-weak px-1 py-[11px] hover:bg-n-slate-3';
export const TARDE = 'shadow-[inset_3px_0_0_rgb(var(--ruby-9))]';
export const QUEM = 'min-w-0 flex-1';
export const NOME = 'block text-[13.5px] font-medium text-n-slate-12';
export const DETALHE = 'block truncate text-[12.5px] text-n-slate-11';
export const HORA =
  'w-11 flex-shrink-0 font-mono text-[12.5px] text-n-slate-11';
export const COL_SELO = 'w-[76px] flex-shrink-0';
export const CAIXA = 'mb-4 rounded-xl border border-n-weak bg-n-slate-2 p-4';
export const CAIXA_TITULO = 'mb-2.5 text-xs font-medium text-n-slate-9';
const BTN =
  'inline-flex items-center gap-1.5 whitespace-nowrap rounded-[7px] border px-2.5 py-[5px] text-[12.5px]';
export const BTN_LINHA = `${BTN} border-n-strong text-n-slate-12 hover:bg-n-slate-3`;
export const BTN_CHEIO = `${BTN} border-n-blue-9 bg-n-blue-9 font-medium text-white hover:brightness-110`;
export const BTN_TINT = `${BTN} border-transparent bg-n-blue-9/[0.08] font-medium text-n-blue-11 dark:bg-n-blue-9/[0.16] disabled:opacity-60`;

// "14:00" / "qui" / "07/10" sempre no fuso do escritório.
export const horaDe = iso =>
  new Date(iso).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: ZONA,
  });
export const diaCurto = iso =>
  new Date(iso)
    .toLocaleDateString('pt-BR', { weekday: 'short', timeZone: ZONA })
    .replace('.', '');
export const diaMes = data => `${data.slice(8, 10)}/${data.slice(5, 7)}`;

// Quanto tempo desde `iso` → chave RAMON.HOJE.{MINUTOS|HORAS|DIAS} + count.
export const desde = (iso, agora = Date.now()) => {
  const minutos = Math.max(0, Math.floor((agora - new Date(iso)) / 60000));
  if (minutos < 60) return { key: 'MINUTOS', count: minutos, minutos };
  if (minutos < 1440)
    return { key: 'HORAS', count: Math.floor(minutos / 60), minutos };
  return { key: 'DIAS', count: Math.floor(minutos / 1440), minutos };
};

// "Rosane, Paulo e Sérgio"
export const juntar = nomes =>
  new Intl.ListFormat('pt-BR', { type: 'conjunction' }).format(nomes);

export const reais = valor =>
  `R$ ${Number(valor || 0).toLocaleString('pt-BR')}`;
