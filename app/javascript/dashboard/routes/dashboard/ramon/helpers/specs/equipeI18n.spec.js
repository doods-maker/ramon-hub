import { execFileSync } from 'node:child_process';
import en from 'dashboard/i18n/locale/en/ramon.json';
import pt from 'dashboard/i18n/locale/pt_BR/ramon.json';

// Trava de sintaxe: "@", "|" e "{" soltos derrubam o render em produção. O vue-i18n escolhe o core
// pelo NODE_ENV na hora do require e o vitest.setup já o carregou em modo teste, em que erro de
// compilação só vira log. Por isso roda em outro processo, com NODE_ENV=production de verdade.
const SCRIPT = `
const { createI18n } = require('vue-i18n/dist/vue-i18n.cjs.prod.js');
const messages = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const { t } = createI18n({
  legacy: false,
  locale: 'x',
  messages: { x: messages },
  missingWarn: false,
  fallbackWarn: false,
}).global;
const tenta = (k, n) => {
  try {
    return t(k, n);
  } catch (e) {
    return '';
  }
};
const saida = {};
Object.keys(messages).forEach(k => {
  saida[k] = [tenta(k, 1), tenta(k, 2)];
});
console.log(JSON.stringify(saida));
`;

const emProducao = messages =>
  JSON.parse(
    execFileSync(process.execPath, ['-e', SCRIPT], {
      input: JSON.stringify(messages),
      env: { ...process.env, NODE_ENV: 'production' },
      encoding: 'utf8',
    })
  );

const quebradas = textos =>
  Object.keys(textos).filter(k => textos[k].some(t => !t.trim()));

describe('RAMON.EQUIPE no vue-i18n de produção', () => {
  it.each([
    ['en', en],
    ['pt_BR', pt],
  ])('%s: nenhuma chave lança nem sai vazia', (_, raiz) => {
    const textos = emProducao(raiz.RAMON.EQUIPE);
    expect(Object.keys(textos)).toContain('SELO_MARCACAO');
    expect(quebradas(textos)).toEqual([]);
    expect(textos.SELO_MARCACAO[0]).toBe('@');
  });

  it('a trava pega sintaxe solta', () => {
    const textos = emProducao({
      OK: 'ok',
      ESCAPADO: "{'@'}",
      ARROBA: '@',
      EMAIL: 'mail a@b.com',
      CHAVE: 'abre { sem fechar',
      PIPE: 'a | ',
    });
    expect(quebradas(textos)).toEqual(['ARROBA', 'EMAIL', 'CHAVE', 'PIPE']);
  });
});
