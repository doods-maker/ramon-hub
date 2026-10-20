import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ChaveManterIa from '../ChaveManterIa.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const montar = chat => {
  const store = createStore({
    state: () => ({ chat }),
    getters: { getSelectedChat: state => state.chat },
  });
  return mount(ChaveManterIa, {
    props: { modelValue: false },
    global: { plugins: [store] },
  });
};

describe('ChaveManterIa.vue', () => {
  it('IA atendendo sozinha: aparece e já vem ligada', () => {
    const wrapper = montar({ id: 1, status: 'pending', custom_attributes: {} });

    expect(wrapper.find('[data-testid="chave-manter-ia"]').exists()).toBe(true);
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([true]);
  });

  it('Só rascunho: aparece desligada (o rascunho ajuda o humano a assumir)', () => {
    const wrapper = montar({
      id: 1,
      status: 'pending',
      custom_attributes: { ia_pausa: 'rascunho' },
    });

    expect(wrapper.find('[data-testid="chave-manter-ia"]').exists()).toBe(true);
    expect(
      wrapper.find('[data-testid="chave-manter-ia-input"]').element.checked
    ).toBe(false);
  });

  it('pessoa atendendo: não aparece', () => {
    const wrapper = montar({
      id: 1,
      status: 'open',
      meta: { assignee: { id: 2, name: 'Eduardo' } },
      custom_attributes: {},
    });

    expect(wrapper.find('[data-testid="chave-manter-ia"]').exists()).toBe(
      false
    );
  });
});
