import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import ChegouCliente from '../ChegouCliente.vue';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import ChegadasAPI from 'dashboard/api/ramonChegadas';
import RamonCalculosAPI from 'dashboard/api/ramonCalculos';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (k, p) => (p ? `${k} ${JSON.stringify(p)}` : k),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useStoreGetters: () => ({
    'agents/getAgents': {
      value: [
        { id: 30, name: 'Tamires de Farias' },
        { id: 20, name: 'Brenda Antunes' },
      ],
    },
  }),
}));
vi.mock('dashboard/api/ramonChegadas', () => ({
  default: { agenda: vi.fn(), create: vi.fn(), get: vi.fn() },
}));
vi.mock('dashboard/api/ramonCalculos', () => ({
  default: { advboxCustomers: vi.fn() },
}));
const dialogOpen = vi.hoisted(() => vi.fn());

// O Dialog real importa CSS (postcss) que não roda no vitest — troca pelo stub.
vi.mock('dashboard/components-next/dialog/Dialog.vue', () => ({
  default: {
    props: ['confirmButtonLabel', 'disableConfirmButton'],
    template: `<div><slot /><button data-testid="confirmar" :disabled="disableConfirmButton" @click="$emit('confirm')">{{ confirmButtonLabel }}</button></div>`,
    methods: { open: dialogOpen, close() {} },
  },
}));
vi.mock('dashboard/components-next/avatar/Avatar.vue', () => ({
  default: { props: ['name'], template: '<span>{{ name }}</span>' },
}));

const agendaMaria = {
  advbox_post_id: 5,
  cliente_nome: 'MARIA SILVA',
  advbox_customer_id: 7,
  notas: 'traz CNIS',
  responsavel_advbox: 'BRENDA ANTUNES',
  destinatario_id: 20,
};

const abrirPainel = async (agenda = []) => {
  ChegadasAPI.agenda.mockResolvedValue({ data: { payload: agenda } });
  ChegadasAPI.get.mockResolvedValue({
    data: { payload: [], pode_avisar: true },
  });
  const store = useChegadasStore();
  store.podeAvisar = true;
  const wrapper = mount(ChegouCliente);
  store.pedirPainel();
  await flushPromises();
  store.podeAvisar = true; // carregar() mockado não pode esconder o painel
  await flushPromises();
  return wrapper;
};

const atendente = (wrapper, nome) =>
  wrapper
    .findAll('[data-testid="atendente"]')
    .find(b => b.text().includes(nome));

describe('ChegouCliente.vue', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  it('some para quem não pode avisar', async () => {
    const wrapper = mount(ChegouCliente);
    useChegadasStore().pedirPainel();
    await flushPromises();
    expect(wrapper.find('[data-testid="chegada-busca"]').exists()).toBe(false);
    expect(dialogOpen).not.toHaveBeenCalled();
  });

  it('abre o painel quando o menu pede', async () => {
    await abrirPainel();
    expect(dialogOpen).toHaveBeenCalled();
  });

  it('não tem mais botão flutuante', () => {
    useChegadasStore().podeAvisar = true;
    const wrapper = mount(ChegouCliente);
    expect(wrapper.find('.fixed.bottom-4').exists()).toBe(false);
  });

  it('agendado de hoje escolhe o cliente e já marca quem atende', async () => {
    const wrapper = await abrirPainel([agendaMaria]);
    await wrapper.find('[data-testid="agenda-item"]').trigger('click');

    expect(wrapper.find('[data-testid="cliente-escolhido"]').text()).toContain(
      'MARIA SILVA'
    );
    expect(atendente(wrapper, 'Brenda').attributes('aria-pressed')).toBe(
      'true'
    );
    expect(atendente(wrapper, 'Brenda').text()).toContain(
      'RAMON.CHEGADA.AGENDADO'
    );
    expect(wrapper.find('[data-testid="confirmar"]').text()).toContain(
      '"nome":"Brenda"'
    );
  });

  it('digitar filtra os agendados sem acento e mostra "usar como digitado"', async () => {
    const wrapper = await abrirPainel([agendaMaria]);
    await wrapper.find('[data-testid="chegada-busca"]').setValue('jo');
    expect(wrapper.find('[data-testid="agenda-item"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="usar-digitado"]').exists()).toBe(true);

    await wrapper.find('[data-testid="chegada-busca"]').setValue('mária');
    expect(wrapper.findAll('[data-testid="agenda-item"]')).toHaveLength(1);
  });

  it('busca no ADVBOX só depois de parar de digitar e a partir de 3 letras', async () => {
    vi.useFakeTimers();
    RamonCalculosAPI.advboxCustomers.mockResolvedValue({
      data: { payload: [{ id: 9, name: 'JOSE PEREIRA' }] },
    });
    const wrapper = await abrirPainel();
    await wrapper.find('[data-testid="chegada-busca"]').setValue('jo');
    vi.advanceTimersByTime(500);
    expect(RamonCalculosAPI.advboxCustomers).not.toHaveBeenCalled();

    await wrapper.find('[data-testid="chegada-busca"]').setValue('jos');
    await wrapper.find('[data-testid="chegada-busca"]').setValue('jose');
    vi.advanceTimersByTime(500);
    await flushPromises();
    expect(RamonCalculosAPI.advboxCustomers).toHaveBeenCalledTimes(1);
    expect(RamonCalculosAPI.advboxCustomers).toHaveBeenCalledWith('jose');

    await wrapper.find('[data-testid="advbox-item"]').trigger('click');
    expect(wrapper.find('[data-testid="cliente-escolhido"]').text()).toContain(
      'JOSE PEREIRA'
    );
    vi.useRealTimers();
  });

  it('avisa com cliente digitado, motivo Reunião e a pessoa escolhida', async () => {
    ChegadasAPI.create.mockResolvedValue({
      data: {
        id: 1,
        cliente_nome: 'Ana',
        estado: 'aguardando',
        criado_por: { id: 1, name: 'Gabriela' },
        destinatario: { id: 30, name: 'Tamires de Farias' },
        created_at: new Date().toISOString(),
      },
    });
    const wrapper = await abrirPainel();
    expect(
      wrapper.find('[data-testid="confirmar"]').attributes('disabled')
    ).toBeDefined();

    await wrapper.find('[data-testid="chegada-busca"]').setValue('Ana');
    await wrapper.find('[data-testid="usar-digitado"]').trigger('click');
    await wrapper.find('[data-testid="motivo-reuniao"]').trigger('click');
    await atendente(wrapper, 'Tamires').trigger('click');
    await wrapper.find('[data-testid="confirmar"]').trigger('click');
    await flushPromises();

    expect(ChegadasAPI.create).toHaveBeenCalledWith(
      expect.objectContaining({
        cliente_nome: 'Ana',
        motivo: 'RAMON.CHEGADA.MOTIVO_REUNIAO',
        destinatario_id: 30,
      })
    );
    expect(wrapper.find('[data-testid="chegada-hoje"]').text()).toContain(
      'Ana'
    );
  });

  it('ADVBOX fora mostra aviso e o nome digitado continua valendo', async () => {
    ChegadasAPI.agenda.mockRejectedValue(new Error('503'));
    useChegadasStore().podeAvisar = true;
    const wrapper = mount(ChegouCliente);
    useChegadasStore().pedirPainel();
    await flushPromises();
    expect(wrapper.text()).toContain('RAMON.CHEGADA.ADVBOX_FORA');
    await wrapper.find('[data-testid="chegada-busca"]').setValue('Ana');
    expect(wrapper.find('[data-testid="usar-digitado"]').exists()).toBe(true);
  });

  it('falha ao avisar mostra erro e mantém o que foi escolhido', async () => {
    ChegadasAPI.create.mockRejectedValue(new Error('422'));
    const wrapper = await abrirPainel([agendaMaria]);
    await wrapper.find('[data-testid="agenda-item"]').trigger('click');
    await wrapper.find('[data-testid="confirmar"]').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('RAMON.CHEGADA.ERRO_AVISAR');
    expect(wrapper.find('[data-testid="cliente-escolhido"]').text()).toContain(
      'MARIA SILVA'
    );
  });
});
