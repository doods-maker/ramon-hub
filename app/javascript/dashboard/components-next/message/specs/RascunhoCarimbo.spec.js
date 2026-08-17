import { mount } from '@vue/test-utils';
import RascunhoCarimbo from '../RascunhoCarimbo.vue';

const translations = {
  'RAMON.COPILOTO.RASCUNHO_IA.igual': () =>
    'rascunho da IA enviado como estava',
  'RAMON.COPILOTO.RASCUNHO_IA.editado': () => 'rascunho da IA, editado',
  'RAMON.COPILOTO.RASCUNHO_IA.descartado': () => 'rascunho da IA descartado',
};
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: k => (translations[k] ? translations[k]() : k) }),
}));

const contentAttributes = {
  value: { ramonRascunhoIa: { notaId: 1, desfecho: 'editado' } },
};
vi.mock('../provider.js', () => ({
  useMessageContext: () => ({ contentAttributes }),
}));

describe('RascunhoCarimbo', () => {
  it('mostra o desfecho', () => {
    const w = mount(RascunhoCarimbo);
    expect(w.text()).toContain('rascunho da IA, editado');
  });
  it('cai no texto de descartado', () => {
    contentAttributes.value = {
      ramonRascunhoIa: { notaId: 2, desfecho: 'descartado' },
    };
    expect(mount(RascunhoCarimbo).text()).toContain('descartado');
  });
});
