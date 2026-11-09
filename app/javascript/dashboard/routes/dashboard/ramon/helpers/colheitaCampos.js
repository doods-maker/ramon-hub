// "O que a IA colheu": achata custom_attributes.colheita.dados (schema do
// Ramon::Colheita::Esquema, um bloco por chave) em linhas { chave, valor,
// confirmar }, só com o que foi preenchido. A chave (ex.: 'acidente.data') é o
// rótulo no i18n RAMON.COLHEITA.CAMPO e o mesmo caminho que a IA usa em
// `confirmar`. Bloco que é lista de objetos (beneficios, queixas…) rende uma
// linha por item, com chave = nome do bloco.
// ponytail: valores ficam como a IA escreveu (já em português: 'sim', 'cessado');
// só datas e sim/não lógico são formatados. Tabela de enum se a equipe estranhar.
const ORDEM = [
  'cliente',
  'beneficios',
  'fechamento',
  'outras_teses_sinal',
  'segurado',
  'saude',
  'incapacidade',
  'dependencia',
  'assistencial',
  'maternidade',
  'ir',
  'qualificacao',
  'acidente',
  'sequela',
  'contrato',
  'queixas',
  'vinculo',
  'responsabilidade',
];

const ISO = /^(\d{4})-(\d{2})-(\d{2})$/;
const data = v => v.replace(ISO, '$3/$2/$1');

const vazio = v =>
  v === null || v === undefined || v === '' || (Array.isArray(v) && !v.length);

const isObj = v => v !== null && typeof v === 'object' && !Array.isArray(v);

// valor de qualquer folha/objeto/lista como texto ('' se não tem nada)
const texto = v => {
  if (typeof v === 'boolean') return v ? 'sim' : 'não';
  if (Array.isArray(v)) {
    const partes = v.map(texto).filter(Boolean);
    return partes.join(v.some(isObj) ? '; ' : ', ');
  }
  if (isObj(v)) {
    return Object.values(v).map(texto).filter(Boolean).join(' · ');
  }
  return vazio(v) ? '' : data(String(v));
};

const beneficio = b =>
  [
    b.especie,
    b.der && `DER ${data(b.der)}`,
    b.dib && `DIB ${data(b.dib)}`,
    b.dcb && `DCB ${data(b.dcb)}`,
    b.situacao,
  ]
    .filter(Boolean)
    .join(' · ');

export const colheitaCampos = (dados, confirmar) => {
  const incertos = new Set(confirmar || []);
  const nomes = Object.keys(dados || {});
  const secoes = [
    ...ORDEM.filter(n => nomes.includes(n)),
    ...nomes.filter(n => !ORDEM.includes(n)),
  ];
  return secoes.flatMap(secao => {
    const bloco = dados[secao];
    if (Array.isArray(bloco)) {
      const formata = secao === 'beneficios' ? beneficio : texto;
      return bloco
        .map(formata)
        .filter(Boolean)
        .map(valor => ({
          chave: secao,
          valor,
          confirmar: incertos.has(secao),
        }));
    }
    return Object.entries(bloco || {})
      .map(([campo, v]) => [campo, texto(v)])
      .filter(([, valor]) => valor)
      .map(([campo, valor]) => {
        const chave = `${secao}.${campo}`;
        return { chave, valor, confirmar: incertos.has(chave) };
      });
  });
};
