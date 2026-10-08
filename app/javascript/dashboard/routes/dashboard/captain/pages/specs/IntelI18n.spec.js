import { createI18n } from 'vue-i18n/dist/vue-i18n.cjs.prod.js';
import en from 'dashboard/i18n/locale/en/ramonIntel.json';
import pt from 'dashboard/i18n/locale/pt_BR/ramonIntel.json';
import { TESES } from '../../responses/teses';

// 8 níveis acima de pages/specs = raiz do repo (só lista os nomes; não lê o conteúdo)
const SEED = import.meta.glob(
  '../../../../../../../../db/seeds/ramon/inteligencia/faq/*.md'
);

const folhas = (obj, prefixo = '') =>
  Object.entries(obj).flatMap(([k, v]) =>
    typeof v === 'object'
      ? folhas(v, `${prefixo}${k}.`)
      : [[`${prefixo}${k}`, v]]
  );

describe('textos da Inteligência (A3)', () => {
  it('en e pt_BR têm as mesmas chaves, na mesma ordem', () => {
    expect(folhas(pt).map(([k]) => k)).toEqual(folhas(en).map(([k]) => k));
  });

  it('cada tese tem rótulo e a lista bate com os arquivos do seed', () => {
    const arquivos = Object.keys(SEED)
      .map(caminho => caminho.split('/').pop().replace('.md', ''))
      .sort();
    expect([...TESES].sort()).toEqual(arquivos);
    TESES.forEach(tese => {
      expect([tese, Boolean(pt.INTEL.TESE[tese])]).toEqual([tese, true]);
      expect([tese, Boolean(en.INTEL.TESE[tese])]).toEqual([tese, true]);
    });
  });

  it.each([
    ['en', en],
    ['pt_BR', pt],
  ])('%s: sem @ | e chaves soltas', (_l, raiz) => {
    folhas(raiz).forEach(([chave, texto]) => {
      const semPlaceholders = texto.replace(/\{[a-z_]+\}/gi, '');
      expect([chave, /[@|{}]/.test(semPlaceholders)]).toEqual([chave, false]);
    });
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
    const params = {
      n: 1,
      id: 1,
      nome: 'x',
      teto: 30,
      tipo: 'x',
      total: 2,
      quando: 'x',
    };
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

  it('chaves da A5 existem nos dois idiomas', () => {
    const A5 = [
      'INTEL.TESTAR.FERRAMENTAS',
      'INTEL.CONFIG.ZONA_RISCO',
      'INTEL.CAIXAS.TITULO',
      'INTEL.VIGIA.CONVERSA',
      'INTEL.CASO_IA.TITULO',
      'INTEL.CADERNO.NOTURNO',
      'INTEL.VISAO_GERAL.CADERNO.LINHA',
      'INTEL.EXECUCOES.PERIODO.D7',
      'INTEL.SKILLS.TESTAR',
      'INTEL.FAQ.USADA',
      'INTEL.DOCUMENTOS.LINK_AVISO',
    ];
    const chavesPt = folhas(pt).map(([k]) => k);
    expect(A5.filter(chave => !chavesPt.includes(chave))).toEqual([]);
  });
});
