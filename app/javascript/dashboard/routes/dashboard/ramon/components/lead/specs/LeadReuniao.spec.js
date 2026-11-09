import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadReuniao from '../LeadReuniao.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const montar = lead =>
  mount(LeadReuniao, {
    props: { lead },
    global: {
      plugins: [
        createStore({
          getters: { getCurrentRole: () => 'agent', getCurrentUserID: () => 1 },
          modules: {
            leads: { namespaced: true, actions: { registrarReuniao: vi.fn() } },
          },
        }),
      ],
      mocks: { $t: k => k },
    },
  });

describe('LeadReuniao', () => {
  it('marca a reunião que veio da IA', () => {
    const wrapper = montar({
      id: 7,
      reuniao_resultado: 'qualificada',
      reuniao_registrada_em: '2026-11-10T15:00:00Z',
      reuniao_pela_ia: true,
    });

    expect(wrapper.find('[data-testid="reuniao-pela-ia"]').exists()).toBe(true);
  });

  it('reunião marcada por uma pessoa não leva a marca', () => {
    const wrapper = montar({
      id: 7,
      reuniao_resultado: 'qualificada',
      reuniao_registrada_em: '2026-11-10T15:00:00Z',
      reuniao_pela_ia: false,
    });

    expect(wrapper.find('[data-testid="reuniao-pela-ia"]').exists()).toBe(
      false
    );
  });
});
