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
    const achados = [];
    if (secao === 'cenarios' && Array.isArray(no)) {
      // ponytail: dos cenários só lead e bom; nome/título vêm do motor
      no.forEach((c, i) => {
        folhas(c?.lead, [secao, i, 'lead'], achados);
        folhas(c?.bom, [secao, i, 'bom'], achados);
      });
    } else {
      folhas(no, [secao], achados);
    }
    achados.forEach(a => saida.push({ secao, ...a }));
  });
  return saida;
};

export const definirTexto = (dados, caminho, valor) => {
  const pai = caminho.slice(0, -1).reduce((no, k) => no?.[k], dados);
  const chave = caminho[caminho.length - 1];
  if (typeof pai?.[chave] !== 'string')
    throw new Error(`Só texto é editável: ${caminho.join('.')}`);
  pai[chave] = valor;
};
