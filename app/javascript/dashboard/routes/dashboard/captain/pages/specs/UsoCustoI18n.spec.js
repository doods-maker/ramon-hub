import { createI18n } from 'vue-i18n/dist/vue-i18n.cjs.prod.js';
import en from 'dashboard/i18n/locale/en/ramonIaUso.json';
import pt from 'dashboard/i18n/locale/pt_BR/ramonIaUso.json';

const folhas = (obj, prefixo = '') =>
  Object.entries(obj).flatMap(([k, v]) =>
    typeof v === 'object'
      ? folhas(v, `${prefixo}${k}.`)
      : [[`${prefixo}${k}`, v]]
  );

describe('textos da tela Uso e custo', () => {
  it('en e pt_BR têm as mesmas chaves', () => {
    expect(folhas(pt).map(([k]) => k)).toEqual(folhas(en).map(([k]) => k));
  });

  // Trava de sintaxe: o compilador de PRODUÇÃO lança em "@" cru (linked message).
  it.each([
    ['en', en],
    ['pt_BR', pt],
  ])('%s: todas as chaves compilam no vue-i18n de produção', (loc, raiz) => {
    const i18n = createI18n({
      legacy: false,
      locale: loc,
      messages: { [loc]: raiz },
      missingWarn: false,
      fallbackWarn: false,
    });
    const params = { n: 1, id: 1, valor: 'x', dia: 'x', custo: 'x' };
    const erros = [];
    folhas(raiz).forEach(([chave]) => {
      try {
        if (i18n.global.t(chave, params) === chave) erros.push(chave);
      } catch (e) {
        erros.push(`${chave}: ${e.message}`);
      }
    });
    expect(erros).toEqual([]);
  });
});
