import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConnectInboxForm from '../ConnectInboxForm.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key),
  }),
}));

const montar = (inboxes = []) => {
  const store = createStore({
    modules: {
      captainInboxes: {
        namespaced: true,
        getters: {
          getUIFlags: () => ({ creatingItem: false }),
          getRecords: () => [],
        },
      },
      inboxes: { namespaced: true, getters: { getInboxes: () => inboxes } },
    },
  });
  return mount(ConnectInboxForm, {
    props: { assistantId: 1 },
    global: { plugins: [store], stubs: { ComboBox: true, Button: true } },
  });
};

describe('ConnectInboxForm — aviso ao conectar', () => {
  afterEach(() => {
    delete window.chatwootConfig;
  });

  it('avisa com o modo padrão do hub (piloto com limites)', () => {
    window.chatwootConfig = { ramonCopilotoModoDefault: 'piloto_limitado' };
    expect(montar().find('[data-testid="aviso-conectar-caixa"]').text()).toBe(
      'CAPTAIN.INBOXES.FORM.AVISO_RASCUNHO {"modo":"RAMON.COPILOTO.MODOS.piloto_limitado.NOME"}'
    );
  });

  it('sem config, o modo do aviso é Rascunho', () => {
    expect(
      montar().find('[data-testid="aviso-conectar-caixa"]').text()
    ).toContain('RAMON.COPILOTO.MODOS.rascunho.NOME');
  });

  it('com a caixa escolhida, avisa com o modo padrão dela', async () => {
    window.chatwootConfig = { ramonCopilotoModoDefault: 'piloto_limitado' };
    const wrapper = montar([
      { id: 7, name: 'Teste', ramon_copiloto_modo: 'piloto_ate_reuniao' },
    ]);
    await wrapper.findComponent(ComboBox).vm.$emit('update:modelValue', 7);
    expect(
      wrapper.find('[data-testid="aviso-conectar-caixa"]').text()
    ).toContain('RAMON.COPILOTO.MODOS.piloto_ate_reuniao.NOME');
  });
});
