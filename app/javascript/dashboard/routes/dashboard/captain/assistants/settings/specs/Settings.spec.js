import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Settings from '../Settings.vue';

const { abrir } = vi.hoisted(() => ({ abrir: vi.fn() }));
const ASSISTENTE = { id: 1, name: 'Atendimento', config: {} };

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1, assistantId: '1' } }),
  useRouter: () => ({ push: vi.fn() }),
}));
// PageLayout puxa o router inteiro (BackButton → routes/index.js): troca pelo esqueleto dos slots.
vi.mock('dashboard/components-next/captain/PageLayout.vue', () => ({
  default: { template: '<div><slot name="body" /><slot /></div>' },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: { 'captainAssistants/getRecord': () => ASSISTENTE },
    dispatch: vi.fn(),
  }),
  useMapGetter: nome =>
    ({
      'captainAssistants/getUIFlags': ref({}),
      'captainAssistants/getRecords': ref([ASSISTENTE]),
    })[nome],
}));
// 'equipe' (não o padrão 'lead'): prova que o público vem do stats. Função pura, não vi.fn: o
// mockReset do vitest.config zeraria o mockResolvedValue antes de cada teste.
vi.mock('dashboard/api/captain/assistant', () => ({
  default: {
    stats: () =>
      Promise.resolve({ data: { payload: [{ id: 1, publico: 'equipe' }] } }),
  },
}));

const montar = () =>
  mount(Settings, {
    global: {
      stubs: {
        Policy: { template: '<div><slot /></div>' },
        SettingsHeader: true,
        AssistantBasicSettingsForm: true,
        AssistantSystemSettingsForm: true,
        AssistantControlItems: true,
        TextoFinal: true,
        Button: {
          props: ['disabled'],
          emits: ['click'],
          template: '<button :disabled="disabled" @click="clicar" />',
          methods: {
            clicar() {
              this.$emit('click');
            },
          },
        },
        DeleteDialog: {
          setup(_, { expose }) {
            expose({ dialogRef: { open: abrir } });
          },
          template: '<i />',
        },
      },
    },
  });

describe('Configurações — zona de risco (I-CF5)', () => {
  it('excluir só libera depois de digitar o nome exato', async () => {
    const wrapper = montar();
    await flushPromises();
    const botao = wrapper.find('[data-testid="zona-de-risco-excluir"]');
    expect(botao.attributes('disabled')).toBeDefined();
    await wrapper
      .find('[data-testid="zona-de-risco-nome"]')
      .setValue('atendimento');
    expect(botao.attributes('disabled')).toBeDefined();
    await wrapper
      .find('[data-testid="zona-de-risco-nome"]')
      .setValue('Atendimento');
    expect(botao.attributes('disabled')).toBeUndefined();
    await botao.trigger('click');
    expect(abrir).toHaveBeenCalled();
  });

  it('passa o público do assistente para os formulários', async () => {
    const wrapper = montar();
    await flushPromises();
    expect(
      wrapper
        .findComponent({ name: 'AssistantBasicSettingsForm' })
        .attributes('publico')
    ).toBe('equipe');
    expect(
      wrapper
        .findComponent({ name: 'AssistantSystemSettingsForm' })
        .attributes('publico')
    ).toBe('equipe');
  });
});
