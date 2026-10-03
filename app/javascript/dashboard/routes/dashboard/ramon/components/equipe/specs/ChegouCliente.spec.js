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

const dialogOpen = vi.hoisted(() => vi.fn());

// O Dialog real importa CSS (postcss) que não roda no vitest — troca pelo stub.
vi.mock('dashboard/components-next/dialog/Dialog.vue', () => ({
  default: {
    template: `<div><slot /><button data-testid="confirmar" @click="$emit('confirm')" /></div>`,
    methods: { open: dialogOpen, close() {} },
  },
}));

const montar = () => mount(ChegouCliente);

describe('ChegouCliente.vue', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  it('some para quem não pode avisar', async () => {
    const wrapper = montar();
    useChegadasStore().pedirPainel();
    await flushPromises();
    expect(wrapper.find('[data-testid="chegada-nome"]').exists()).toBe(false);
    expect(dialogOpen).not.toHaveBeenCalled();
  });

  it('abre o painel quando o menu pede', async () => {
    ChegadasAPI.agenda.mockResolvedValue({ data: { payload: [] } });
    useChegadasStore().podeAvisar = true;
    montar();
    useChegadasStore().pedirPainel();
    await flushPromises();
    expect(dialogOpen).toHaveBeenCalled();
  });

  it('não tem mais botão flutuante', () => {
    useChegadasStore().podeAvisar = true;
    const wrapper = montar();
    expect(wrapper.find('.fixed.bottom-4').exists()).toBe(false);
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
    useChegadasStore().pedirPainel();
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
    useChegadasStore().pedirPainel();
    await flushPromises();
    expect(wrapper.text()).toContain('RAMON.CHEGADA.ADVBOX_FORA');
  });

  it('falha ao avisar mostra erro e mantém o formulário', async () => {
    ChegadasAPI.agenda.mockResolvedValue({ data: { payload: [] } });
    ChegadasAPI.create.mockRejectedValue(new Error('422'));
    useChegadasStore().podeAvisar = true;
    const wrapper = montar();
    useChegadasStore().pedirPainel();
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(b => b.text() === 'RAMON.CHEGADA.ABA_LIVRE')
      .trigger('click');
    await wrapper.find('[data-testid="chegada-nome"]').setValue('JOSE');
    await wrapper.find('[data-testid="chegada-destinatario"]').setValue('20');
    await wrapper.find('[data-testid="confirmar"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('RAMON.CHEGADA.ERRO_AVISAR');
    expect(wrapper.find('[data-testid="chegada-nome"]').element.value).toBe(
      'JOSE'
    );
  });
});
