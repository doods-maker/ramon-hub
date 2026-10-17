import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConnectInboxForm from '../ConnectInboxForm.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const montar = () => {
  const store = createStore({
    modules: {
      captainInboxes: {
        namespaced: true,
        getters: {
          getUIFlags: () => ({ creatingItem: false }),
          getRecords: () => [],
        },
      },
      inboxes: { namespaced: true, getters: { getInboxes: () => [] } },
    },
  });
  return mount(ConnectInboxForm, {
    props: { assistantId: 1 },
    global: {
      plugins: [store],
      stubs: {
        ComboBox: true,
        Button: true,
        'router-link': { props: ['to'], template: '<a><slot /></a>' },
      },
    },
  });
};

describe('ConnectInboxForm — aviso ao conectar', () => {
  it('aponta para Como a IA atende, sem falar de modo', () => {
    const aviso = montar().find('[data-testid="aviso-conectar-caixa"]');
    expect(aviso.text()).toContain('CAPTAIN.INBOXES.FORM.AVISO_COMO_IA_ATENDE');
    expect(aviso.text()).toContain(
      'INBOX_MGMT.SETTINGS_POPUP.RAMON_IA_ATENDE.LINK'
    );
  });
});
