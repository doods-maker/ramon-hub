import { createI18n } from 'vue-i18n/dist/vue-i18n.cjs.prod.js';
import en from 'dashboard/i18n/locale/en/ramon.json';
import pt from 'dashboard/i18n/locale/pt_BR/ramon.json';

// Blocos de texto da Inteligência A4 (menu "Virar FAQ" e atalhos do Copiloto).
const BLOCOS = ['FAQ_CONVERSA', 'COPILOTO_ATALHOS'];

const folhas = (obj, prefixo = '') =>
  Object.entries(obj).flatMap(([k, v]) =>
    typeof v === 'object'
      ? folhas(v, `${prefixo}${k}.`)
      : [[`${prefixo}${k}`, v]]
  );

describe.each(BLOCOS)('textos da A4: %s', bloco => {
  const textosEn = en.CAPTAIN_RAMON[bloco];
  const textosPt = pt.CAPTAIN_RAMON[bloco];

  it('en e pt_BR têm as mesmas chaves, na mesma ordem', () => {
    expect(folhas(textosPt).map(([k]) => k)).toEqual(
      folhas(textosEn).map(([k]) => k)
    );
  });

  it.each([
    ['en', textosEn],
    ['pt_BR', textosPt],
  ])('%s: sem @ | e chaves soltas', (_l, textos) => {
    folhas(textos).forEach(([chave, texto]) => {
      expect([chave, /[@|{}]/.test(texto)]).toEqual([chave, false]);
    });
  });

  // Trava de sintaxe: o compilador de PRODUÇÃO lança em qualquer erro.
  it.each([
    ['en', en, textosEn],
    ['pt_BR', pt, textosPt],
  ])('%s: compila no vue-i18n de produção', (loc, raiz, textos) => {
    const i18n = createI18n({
      legacy: false,
      locale: loc,
      messages: { [loc]: raiz },
      missingWarn: false,
      fallbackWarn: false,
    });
    const erros = [];
    folhas(textos).forEach(([chave]) => {
      const completa = `CAPTAIN_RAMON.${bloco}.${chave}`;
      try {
        if (i18n.global.t(completa) === completa) erros.push(completa);
      } catch (e) {
        erros.push(`${completa}: ${e.message}`);
      }
    });
    expect(erros).toEqual([]);
  });
});
