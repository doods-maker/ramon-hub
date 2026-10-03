import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import AlertaChegada from '../AlertaChegada.vue';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import ChegadasAPI from 'dashboard/api/ramonChegadas';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({ getCurrentUserID: { value: 20 } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
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
  enableAutoUnmount(afterEach);

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
    await wrapper.find('[data-testid="chegada-outra-coisa"]').trigger('click');
    await wrapper.find('[data-testid="chegada-resposta"]').setValue('já vou');
    play.mockClear();
    store.upsert(chegada(4, { estado: 'escalado' }));
    await flushPromises();
    expect(wrapper.find('[data-testid="chegada-resposta"]').element.value).toBe(
      'já vou'
    );
    expect(play).not.toHaveBeenCalled();
  });

  it('reconexão do websocket recarrega as chegadas', async () => {
    mount(AlertaChegada);
    await flushPromises();
    ChegadasAPI.get.mockClear();
    emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT);
    await flushPromises();
    expect(ChegadasAPI.get).toHaveBeenCalledTimes(1);
  });

  it('avisa quem criou quando o destinatário responde', async () => {
    mount(AlertaChegada);
    await flushPromises();
    const store = useChegadasStore();
    const minha = {
      criado_por: { id: 20, name: 'Eu' },
      destinatario: { id: 30, name: 'Tamires' },
    };
    store.upsert(chegada(5, minha));
    await flushPromises();
    store.upsert(
      chegada(5, { ...minha, estado: 'respondido', resposta: 'já vou' })
    );
    await flushPromises();
    store.upsert(
      chegada(5, { ...minha, estado: 'respondido', resposta: 'já vou' })
    );
    await flushPromises();
    expect(useAlert).toHaveBeenCalledTimes(1);
    expect(useAlert).toHaveBeenCalledWith('RAMON.CHEGADA.RESPONDEU');
  });

  describe('tela cheia (redesign v2)', () => {
    afterEach(() => vi.useRealTimers());

    it.each([
      [0, 'RAMON.CHEGADA.ATENDER_AGORA'],
      [1, 'RAMON.CHEGADA.AGUARDAR'],
      [2, 'RAMON.CHEGADA.NAO_POSSO'],
    ])('resposta pronta %i responde com o texto do botão', async (i, texto) => {
      ChegadasAPI.responder.mockResolvedValue({
        data: chegada(6, { estado: 'respondido', resposta: texto }),
      });
      const wrapper = mount(AlertaChegada);
      await flushPromises();
      useChegadasStore().upsert(chegada(6));
      await flushPromises();
      await wrapper
        .find(`[data-testid="chegada-rapida-${i}"]`)
        .trigger('click');
      await flushPromises();
      expect(ChegadasAPI.responder).toHaveBeenCalledWith(6, texto);
    });

    it('conta o tempo até o aviso voltar pra quem avisou', async () => {
      vi.useFakeTimers({ toFake: ['Date', 'setInterval', 'clearInterval'] });
      vi.setSystemTime(new Date('2026-10-03T16:55:19Z'));
      const wrapper = mount(AlertaChegada);
      await flushPromises();
      useChegadasStore().upsert(
        chegada(7, { created_at: '2026-10-03T16:55:00Z' })
      );
      await flushPromises();
      const volta = wrapper.find('[data-testid="chegada-volta-em"]');
      expect(volta.exists()).toBe(true);
      expect(wrapper.vm.voltaEm).toBe('2:41');
      expect(wrapper.text()).toContain('RAMON.CHEGADA.AVISADO_POR');
    });

    it('escalada não mostra contagem nem respostas prontas', async () => {
      const wrapper = mount(AlertaChegada);
      await flushPromises();
      useChegadasStore().upsert(
        chegada(8, {
          estado: 'escalado',
          created_at: '2026-10-03T16:55:00Z',
          criado_por: { id: 20, name: 'Eu' },
          destinatario: { id: 30, name: 'Tamires' },
        })
      );
      await flushPromises();
      expect(wrapper.find('[data-testid="chegada-volta-em"]').exists()).toBe(
        false
      );
      expect(wrapper.find('[data-testid="chegada-rapida-0"]').exists()).toBe(
        false
      );
    });
  });
});
