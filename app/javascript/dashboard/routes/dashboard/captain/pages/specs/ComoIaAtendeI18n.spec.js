import { createI18n } from 'vue-i18n/dist/vue-i18n.cjs.prod.js';
import en from 'dashboard/i18n/locale/en/ramon.json';
import pt from 'dashboard/i18n/locale/pt_BR/ramon.json';
import enSettings from 'dashboard/i18n/locale/en/settings.json';
import ptSettings from 'dashboard/i18n/locale/pt_BR/settings.json';

const folhas = (obj, prefixo = '') =>
  Object.entries(obj).flatMap(([k, v]) =>
    typeof v === 'object'
      ? folhas(v, `${prefixo}${k}.`)
      : [[`${prefixo}${k}`, v]]
  );

describe('textos da tela Como a IA atende', () => {
  const textos = { en: en.RAMON.COMO_IA, pt_BR: pt.RAMON.COMO_IA };

  it('en e pt_BR têm as mesmas chaves (e o item do menu)', () => {
    expect(folhas(textos.pt_BR).map(([k]) => k)).toEqual(
      folhas(textos.en).map(([k]) => k)
    );
    expect(ptSettings.SIDEBAR.CAPTAIN_COMO_IA).toBe('Como a IA atende');
    expect(enSettings.SIDEBAR.CAPTAIN_COMO_IA).toBe('How the AI works');
  });

  // Trava de sintaxe: o compilador de PRODUÇÃO lança em "@" cru (linked message) e em "|" vira plural.
  it.each(['en', 'pt_BR'])(
    '%s: todas as chaves compilam no vue-i18n de produção',
    loc => {
      const i18n = createI18n({
        legacy: false,
        locale: loc,
        messages: { [loc]: { RAMON: { COMO_IA: textos[loc] } } },
        missingWarn: false,
        fallbackWarn: false,
      });
      const params = { n: 2, perfil: 'x', etapa: 'x', acao: 'x', valor: 'x' };
      const erros = [];
      folhas(textos[loc]).forEach(([chave, texto]) => {
        if (/[@|]/.test(texto)) erros.push(`${chave}: @ ou |`);
        try {
          const caminho = `RAMON.COMO_IA.${chave}`;
          if (
            i18n.global.t(caminho, { ...params, ate: 'a', depois: 'b' }) ===
            caminho
          )
            erros.push(chave);
        } catch (e) {
          erros.push(`${chave}: ${e.message}`);
        }
      });
      expect(erros).toEqual([]);
    }
  );
});
