// "O que a IA colheu": achata custom_attributes.colheita.dados (schema do
// Ramon::ColheitaExtractionService) em linhas { chave, valor, confirmar }, só
// com o que foi preenchido. A chave (ex.: 'acidente.data') é o rótulo no i18n
// RAMON.COLHEITA.CAMPO e o mesmo caminho que a IA usa em `confirmar`.
// ponytail: valores ficam como a IA escreveu (já em português: 'sim', 'cessado');
// só datas e sim/não lógico são formatados. Tabela de enum se a equipe estranhar.
const SECOES = [
  'cliente',
  'qualificacao',
  'acidente',
  'sequela',
  'beneficios',
  'fechamento',
];

const ISO = /^(\d{4})-(\d{2})-(\d{2})$/;
const data = v => v.replace(ISO, '$3/$2/$1');

const vazio = v =>
  v === null || v === undefined || v === '' || (Array.isArray(v) && !v.length);

const texto = v => {
  if (typeof v === 'boolean') return v ? 'sim' : 'não';
  if (Array.isArray(v)) return v.join(', ');
  return data(String(v));
};

const beneficio = b =>
  [
    b.especie,
    b.dib && `DIB ${data(b.dib)}`,
    b.dcb && `DCB ${data(b.dcb)}`,
    b.situacao,
  ]
    .filter(Boolean)
    .join(' · ');

export const colheitaCampos = (dados, confirmar) => {
  const incertos = new Set(confirmar || []);
  return SECOES.flatMap(secao => {
    const bloco = dados?.[secao];
    if (secao === 'beneficios') {
      return (Array.isArray(bloco) ? bloco : [])
        .map(beneficio)
        .filter(Boolean)
        .map(valor => ({
          chave: 'beneficios',
          valor,
          confirmar: incertos.has('beneficios'),
        }));
    }
    return Object.entries(bloco || {})
      .filter(([, v]) => !vazio(v))
      .map(([campo, v]) => {
        const chave = `${secao}.${campo}`;
        return { chave, valor: texto(v), confirmar: incertos.has(chave) };
      });
  });
};
