import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import AlertaChegada from '../AlertaChegada.vue';
import { useChegadasStore } from 'dashboard/stores/chegadas';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({ getCurrentUserID: { value: 20 } }),
}));
vi.mock('dashboard/api/ramonChegadas', () => ({
  default: {
    get: vi
      .fn()
      .mockResolvedValue({ data: { payload: [], pode_avisar: false } }),
    responder: vi.fn(),
  },
}));

const play = vi.fn().mockResolvedValue();
const pause = vi.fn();
vi.stubGlobal(
  'Audio',
  class {
    constructor() {
      this.play = play;
      this.pause = pause;
      this.loop = false;
      this.currentTime = 0;
    }
  }
);

const chegada = (id, over = {}) => ({
  id,
  cliente_nome: `Cliente ${id}`,
  motivo: null,
  estado: 'aguardando',
  criado_por: { id: 10, name: 'Gabriela' },
  destinatario: { id: 20, name: 'Brenda' },
  ...over,
});

describe('AlertaChegada.vue', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    play.mockReset().mockResolvedValue();
    pause.mockClear();
  });

  it('toca e mostra a fila; responder a 1ª revela a 2ª; última resposta para o toque', async () => {
    const wrapper = mount(AlertaChegada);
    await flushPromises();
    const store = useChegadasStore();
    pause.mockClear(); // pause() inicial do mount sem alerta é inofensivo
    store.upsert(chegada(1));
    store.upsert(chegada(2));
    await flushPromises();

    expect(wrapper.text()).toContain('Cliente 1');
    expect(wrapper.text()).toContain('RAMON.CHEGADA.MAIS');
    expect(play).toHaveBeenCalled();

    store.upsert(chegada(1, { estado: 'respondido' }));
    await flushPromises();
    expect(wrapper.text()).toContain('Cliente 2');
    expect(pause).not.toHaveBeenCalled();

    store.upsert(chegada(2, { estado: 'respondido' }));
    await flushPromises();
    expect(wrapper.find('[data-testid="alerta-chegada"]').exists()).toBe(false);
    expect(pause).toHaveBeenCalled();
  });

  it('escalada pra quem avisou mostra "Entendi" em vez do campo de resposta', async () => {
    const wrapper = mount(AlertaChegada);
    await flushPromises();
    useChegadasStore().upsert(
      chegada(3, {
        estado: 'escalado',
        criado_por: { id: 20, name: 'Eu' },
        destinatario: { id: 30, name: 'Tamires' },
      })
    );
    await flushPromises();
    expect(wrapper.find('[data-testid="chegada-resposta"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain('RAMON.CHEGADA.ENTENDI');
  });

  it('escalar a mesma chegada não apaga a resposta digitada', async () => {
    const wrapper = mount(AlertaChegada);
    await flushPromises();
    const store = useChegadasStore();
    store.upsert(chegada(4));
    await flushPromises();
    await wrapper.find('[data-testid="chegada-resposta"]').setValue('já vou');
    play.mockClear();
    store.upsert(chegada(4, { estado: 'escalado' }));
    await flushPromises();
    expect(wrapper.find('[data-testid="chegada-resposta"]').element.value).toBe(
      'já vou'
    );
    expect(play).not.toHaveBeenCalled();
  });
});
