import { mount, flushPromises } from '@vue/test-utils';
import RamonBuscaAPI from 'dashboard/api/ramonBusca';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import CommandPalette from '../CommandPalette.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const routerPush = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push: routerPush }) }));

let keyHandlers = {};
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: events => {
    keyHandlers = events;
  },
}));

vi.mock('dashboard/api/ramonBusca', () => ({ default: { get: vi.fn() } }));

const resposta = {
  leads: [
    {
      id: 7,
      nome: 'João Pedro Martins',
      tese: 'Auxílio-acidente',
      telefone: '+5547996342210',
      stage_name: 'Em qualificação',
      stage_color: '#0369A1',
    },
    { id: 8, nome: 'João Paulo Ramos', tese: null, telefone: null },
  ],
  clientes: [],
  processos: [
    {
      numero: '5001876-22.2023.4.04.7216',
      tipo: 'Auxílio-doença',
      cliente: 'João Paulo Ramos',
      cliente_id: 3,
    },
  ],
};

const mountPalette = () =>
  mount(CommandPalette, {
    attachTo: document.body,
    global: { mocks: { $t: k => k } },
  });

const abrir = async wrapper => {
  keyHandlers['$mod+KeyK'].action({ preventDefault: vi.fn() });
  await wrapper.vm.$nextTick();
};

describe('CommandPalette', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    RamonBuscaAPI.get.mockReset();
    RamonBuscaAPI.get.mockResolvedValue({ data: resposta });
    routerPush.mockClear();
  });
  afterEach(() => vi.useRealTimers());

  it('abre com Ctrl+K e pelo evento do botão Buscar; Esc fecha', async () => {
    const wrapper = mountPalette();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    await abrir(wrapper);
    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    await wrapper.find('input').trigger('keydown', { key: 'Escape' });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    emitter.emit(BUS_EVENTS.OPEN_COMMAND_BAR);
    await wrapper.vm.$nextTick();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('não chama a API com 1 letra', async () => {
    const wrapper = mountPalette();
    await abrir(wrapper);
    await wrapper.find('input').setValue('j');
    vi.advanceTimersByTime(500);
    expect(RamonBuscaAPI.get).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('chama com "joao p" depois do debounce e mostra os grupos', async () => {
    const wrapper = mountPalette();
    await abrir(wrapper);
    await wrapper.find('input').setValue('joao p');
    vi.advanceTimersByTime(249);
    expect(RamonBuscaAPI.get).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(RamonBuscaAPI.get).toHaveBeenCalledWith('joao p');
    await flushPromises();
    expect(wrapper.text()).toContain('João Pedro Martins');
    expect(wrapper.text()).toContain('5001876-22.2023.4.04.7216');
    expect(wrapper.text()).toContain('Em qualificação');
    wrapper.unmount();
  });

  it('↓ + Enter abre o 2º item', async () => {
    const wrapper = mountPalette();
    await abrir(wrapper);
    const input = wrapper.find('input');
    await input.setValue('joao');
    vi.advanceTimersByTime(250);
    await flushPromises();
    await input.trigger('keydown', { key: 'ArrowDown' });
    await input.trigger('keydown', { key: 'Enter' });
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_lead_dossie',
      params: { leadId: 8 },
    });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('"Mais comandos…" fecha a paleta e emite OPEN_NINJA', async () => {
    const ouvinte = vi.fn();
    emitter.on(BUS_EVENTS.OPEN_NINJA, ouvinte);
    const wrapper = mountPalette();
    await abrir(wrapper);
    await wrapper.find('[data-testid="cmd-acao-mais"]').trigger('click');
    expect(ouvinte).toHaveBeenCalled();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    emitter.off(BUS_EVENTS.OPEN_NINJA, ouvinte);
    wrapper.unmount();
  });

  it('processo abre o painel do cliente já filtrado pelo nome', async () => {
    const wrapper = mountPalette();
    await abrir(wrapper);
    await wrapper.find('input').setValue('5001876');
    vi.advanceTimersByTime(250);
    await flushPromises();
    await wrapper
      .find('[data-testid="cmd-processo-5001876-22.2023.4.04.7216"]')
      .trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_portal_clientes',
      query: { q: 'João Paulo Ramos' },
    });
    wrapper.unmount();
  });

  it('resposta que chega depois de fechar é descartada', async () => {
    let resolver;
    RamonBuscaAPI.get.mockReturnValue(
      new Promise(r => {
        resolver = r;
      })
    );
    const wrapper = mountPalette();
    await abrir(wrapper);
    await wrapper.find('input').setValue('joao');
    vi.advanceTimersByTime(250);
    await wrapper.find('input').trigger('keydown', { key: 'Escape' });
    resolver({ data: resposta });
    await flushPromises();
    await abrir(wrapper);
    expect(wrapper.text()).not.toContain('João Pedro Martins');
    wrapper.unmount();
  });

  it('Esc e setas funcionam com o foco num resultado', async () => {
    const wrapper = mountPalette();
    await abrir(wrapper);
    const botao = wrapper.find('[data-testid="cmd-acao-novo-calculo"]');
    await botao.trigger('keydown', { key: 'ArrowDown' });
    await botao.trigger('keydown', { key: 'Enter' });
    expect(routerPush).toHaveBeenCalledWith({ name: 'ramon_calculos' });
    wrapper.unmount();
  });
});
