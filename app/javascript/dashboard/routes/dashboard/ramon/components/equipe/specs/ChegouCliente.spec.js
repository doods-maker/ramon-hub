import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import ChegouCliente from '../ChegouCliente.vue';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import ChegadasAPI from 'dashboard/api/ramonChegadas';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useStoreGetters: () => ({
    'agents/getAgents': { value: [{ id: 20, name: 'Brenda' }] },
  }),
}));
vi.mock('dashboard/api/ramonChegadas', () => ({
  default: { agenda: vi.fn(), create: vi.fn() },
}));
vi.mock('dashboard/api/ramonCalculos', () => ({
  default: { advboxCustomers: vi.fn() },
}));

// O Dialog real importa CSS (postcss) que não roda no vitest — troca pelo stub.
vi.mock('dashboard/components-next/dialog/Dialog.vue', () => ({
  default: {
    template: '<div><slot /></div>',
    methods: { open() {}, close() {} },
  },
}));

const montar = () => mount(ChegouCliente);

describe('ChegouCliente.vue', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('some para quem não pode avisar', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-testid="chegou-cliente-botao"]').exists()).toBe(
      false
    );
  });

  it('clicar em quem vem hoje preenche cliente e sugere quem atende', async () => {
    ChegadasAPI.agenda.mockResolvedValue({
      data: {
        payload: [
          {
            advbox_post_id: 5,
            cliente_nome: 'MARIA SILVA',
            advbox_customer_id: 7,
            notas: 'traz CNIS',
            responsavel_advbox: 'BRENDA',
            destinatario_id: 20,
          },
        ],
      },
    });
    useChegadasStore().podeAvisar = true;
    const wrapper = montar();
    await wrapper.find('[data-testid="chegou-cliente-botao"]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-testid="agenda-item"]').trigger('click');

    expect(wrapper.find('[data-testid="chegada-nome"]').element.value).toBe(
      'MARIA SILVA'
    );
    expect(
      wrapper.find('[data-testid="chegada-destinatario"]').element.value
    ).toBe('20');
  });

  it('ADVBOX fora mostra aviso', async () => {
    ChegadasAPI.agenda.mockRejectedValue(new Error('503'));
    useChegadasStore().podeAvisar = true;
    const wrapper = montar();
    await wrapper.find('[data-testid="chegou-cliente-botao"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('RAMON.CHEGADA.ADVBOX_FORA');
  });
});
