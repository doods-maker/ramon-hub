// Painel do time: cor do cartão pela meta do plano (doc 04 §4).
// Verde = dentro da meta; âmbar = perto (até 10 pontos percentuais da meta,
// ou até 2 min a mais na 1ª resposta); vermelho = cobrar. Contagem (sem
// resposta agora) não tem folga: acima da meta já é cobrar.
const FOLGA = { '%': 10, min: 2, n: 0 };

// meta = { alvo, sentido: 'min' (≥) | 'max' (≤), unidade: '%' | 'min' | 'n' }
// valor nulo (sem denominador) = sem status.
export const statusKpi = (valor, meta) => {
  if (valor == null || !meta) return null;
  const sobra = meta.sentido === 'min' ? valor - meta.alvo : meta.alvo - valor;
  if (sobra >= 0) return 'ok';
  return -sobra <= FOLGA[meta.unidade] ? 'atencao' : 'cobrar';
};

// status → cor do kit (FILETE/TOM do helpers/ui)
export const COR_STATUS = { ok: 'teal', atencao: 'amber', cobrar: 'ruby' };

const numero = (valor, casas) =>
  valor.toLocaleString('pt-BR', { maximumFractionDigits: casas });

// "71%", "6,5min", "2" — valor nulo vira travessão.
export const formatarKpi = (valor, unidade) => {
  if (valor == null) return '—';
  if (unidade === '%') return `${numero(valor, 0)}%`;
  if (unidade === 'min') return `${numero(valor, 1)}min`;
  return numero(valor, 0);
};
