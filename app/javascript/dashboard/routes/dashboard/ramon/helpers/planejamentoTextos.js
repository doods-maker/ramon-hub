// Só texto (folhas string) do `dados` do planejamento é editável no hub;
// número, booleano e null nunca. Chaves desconhecidas são tratadas de forma genérica.
export const SECOES_EDITAVEIS = [
  'pendencias',
  'observacoes_internas',
  'pode',
  'nao_pode',
  'sugestao',
  'cenarios',
  'melhorias',
  'passos',
  'conferir',
  'documentos',
];

// Seções que são listas de itens: só estas chaves de cada item são texto livre
// (nome, título, data e regra vêm do motor e alimentam o PDF/recálculo).
export const ITENS_EDITAVEIS = {
  pendencias: ['t', 'p'],
  observacoes_internas: ['t', 'p'],
  cenarios: ['lead', 'bom'],
  melhorias: ['t', 'p'],
};
// Na versão curta (já tem direito) estas seções não vão no PDF: não editar.
const SO_NA_COMPLETA = ['cenarios', 'sugestao', 'conferir'];

const folhas = (no, caminho, saida) => {
  if (typeof no === 'string') saida.push({ caminho, valor: no });
  else if (Array.isArray(no))
    no.forEach((v, i) => folhas(v, [...caminho, i], saida));
  else if (no && typeof no === 'object')
    Object.keys(no).forEach(k => folhas(no[k], [...caminho, k], saida));
};

export const camposEditaveis = dados => {
  const saida = [];
  SECOES_EDITAVEIS.forEach(secao => {
    const no = dados?.[secao];
    if (no === undefined || no === null) return;
    if (dados.versao === 'curta' && SO_NA_COMPLETA.includes(secao)) return;
    const achados = [];
    const chaves = ITENS_EDITAVEIS[secao];
    if (chaves && Array.isArray(no)) {
      no.forEach((item, i) =>
        chaves.forEach(k => folhas(item?.[k], [secao, i, k], achados))
      );
    } else {
      folhas(no, [secao], achados);
    }
    achados.forEach(a => saida.push({ secao, ...a }));
  });
  return saida;
};

export const definirTexto = (dados, caminho, valor) => {
  const alvo = caminho.join('.');
  if (!camposEditaveis(dados).some(c => c.caminho.join('.') === alvo))
    throw new Error(`Só texto das seções editáveis: ${alvo}`);
  const pai = caminho.slice(0, -1).reduce((no, k) => no[k], dados);
  pai[caminho[caminho.length - 1]] = valor;
};
