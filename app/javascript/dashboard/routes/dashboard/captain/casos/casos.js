// Regras puras da tela Casos de teste (filtro, placar por caso, formatos).

export const ATIVAS = ['fila', 'rodando'];

export const rodadaAtiva = rodada => ATIVAS.includes(rodada?.status);

const semAcento = texto =>
  (texto || '')
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase();

// filtroAtivo: '' (todos) | 'ativos' | 'inativos'
export const filtrarCasos = (casos, { busca = '', grupo = '', ativo = '' }) => {
  const termo = semAcento(busca.trim());
  return casos.filter(caso => {
    if (grupo && caso.grupo !== grupo) return false;
    if (ativo === 'ativos' && !caso.ativo) return false;
    if (ativo === 'inativos' && caso.ativo) return false;
    if (!termo) return true;
    const falas = (caso.mensagens || []).map(fala => fala.content).join(' ');
    return semAcento(`${caso.titulo} ${falas}`).includes(termo);
  });
};

export const gruposDe = casos =>
  [...new Set(casos.map(caso => caso.grupo).filter(Boolean))].sort();

// caso_id → { ...resultado, delta: 'piorou' | 'melhorou' | null }
export const resultadoPorCaso = rodada => {
  const pioraram = new Set(rodada?.comparacao?.pioraram || []);
  const melhoraram = new Set(rodada?.comparacao?.melhoraram || []);
  const mapa = {};
  (rodada?.resultados || []).forEach(item => {
    let delta = null;
    if (pioraram.has(item.caso_id)) delta = 'piorou';
    if (melhoraram.has(item.caso_id)) delta = 'melhorou';
    mapa[item.caso_id] = { ...item, delta };
  });
  return mapa;
};

// Piorou primeiro (é o que importa depois de um ajuste), depois falhou.
export const ordenarPorAtencao = (casos, resultados) => {
  const peso = caso => {
    const resultado = resultados[caso.id];
    if (resultado?.delta === 'piorou') return 0;
    if (resultado && !resultado.passou) return 1;
    return 2;
  };
  return [...casos].sort((a, b) => peso(a) - peso(b));
};

export const fmtUsd = valor =>
  `US$ ${Number(valor || 0).toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;

export const fmtDuracao = ms => {
  const segundos = Math.round((ms || 0) / 1000);
  if (segundos < 60) return `${segundos}s`;
  return `${Math.floor(segundos / 60)}min ${segundos % 60}s`;
};

export const fmtQuando = valor =>
  new Date(valor).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

// Campo de lista do formulário: uma por linha (ou vírgula, nas ferramentas).
export const paraLista = (texto, separador = /\n/) =>
  (texto || '')
    .split(separador)
    .map(item => item.trim())
    .filter(Boolean);
