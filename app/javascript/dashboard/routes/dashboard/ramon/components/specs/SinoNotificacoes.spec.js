import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import NotificationsAPI from 'dashboard/api/notifications';
import SinoNotificacoes from '../SinoNotificacoes.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
const routerPush = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push: routerPush }) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));
vi.mock('dashboard/api/notifications', () => ({
  default: { update: vi.fn(() => Promise.resolve()) },
}));

const dispatch = vi.fn(() => Promise.resolve());
const metaRef = ref({ unreadCount: 0 });
const listaRef = ref([]);
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: key => (key === 'notifications/getMeta' ? metaRef : listaRef),
}));

const avisoDoHub = {
  id: 2,
  notification_type: 'ramon_fluxo_aviso',
  primary_actor_type: 'Lead',
  primary_actor_id: 40,
  primary_actor: { id: 40, conversation_id: null },
  push_message_title: 'Automação: Lead parado há 3 dias (Maria)',
  push_message_body: 'Automação: Lead parado há 3 dias (Maria)',
  meta: { label: 'Lead parado há 3 dias' },
  read_at: null,
  created_at: 1760900000,
};

const montar = () =>
  mount(SinoNotificacoes, {
    global: { stubs: { 'router-link': { template: '<a><slot /></a>' } } },
  });

describe('SinoNotificacoes.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    metaRef.value = { unreadCount: 0 };
    listaRef.value = [];
  });

  it('busca a contagem ao montar e mostra o número de não lidas', async () => {
    metaRef.value = { unreadCount: 3 };
    const wrapper = montar();
    expect(dispatch).toHaveBeenCalledWith('notifications/unReadCount');
    expect(wrapper.find('[data-testid="sino-contagem"]').text()).toBe('3');

    metaRef.value = { unreadCount: 120 };
    await flushPromises();
    expect(wrapper.find('[data-testid="sino-contagem"]').text()).toBe('99+');
  });

  it('sem não lidas não mostra contagem', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-testid="sino-contagem"]').exists()).toBe(false);
  });

  it('abre o painel, carrega a lista e mostra o aviso do hub pelo texto', async () => {
    listaRef.value = [avisoDoHub];
    const wrapper = montar();
    await wrapper.find('[data-testid="sino"]').trigger('click');
    expect(dispatch).toHaveBeenCalledWith('notifications/get');
    const itens = wrapper.findAll('[data-testid="sino-item"]');
    expect(itens).toHaveLength(1);
    expect(itens[0].text()).toContain('Lead parado há 3 dias (Maria)');
  });

  it('usa o label do meta quando não vem título', async () => {
    listaRef.value = [
      { ...avisoDoHub, push_message_title: '', push_message_body: '' },
    ];
    const wrapper = montar();
    await wrapper.find('[data-testid="sino"]').trigger('click');
    expect(wrapper.find('[data-testid="sino-item"]').text()).toContain(
      'Lead parado há 3 dias'
    );
  });

  it('"Marcar todas como lidas" despacha o readAll', async () => {
    metaRef.value = { unreadCount: 1 };
    listaRef.value = [avisoDoHub];
    const wrapper = montar();
    await wrapper.find('[data-testid="sino"]').trigger('click');
    await wrapper.find('[data-testid="sino-marcar-todas"]').trigger('click');
    expect(dispatch).toHaveBeenCalledWith('notifications/readAll');
  });

  it('clique no aviso de lead sem conversa marca só ele e abre a ficha', async () => {
    listaRef.value = [avisoDoHub];
    const wrapper = montar();
    await wrapper.find('[data-testid="sino"]').trigger('click');
    await wrapper.find('[data-testid="sino-item"]').trigger('click');
    expect(NotificationsAPI.update).toHaveBeenCalledWith(2, {});
    expect(dispatch).not.toHaveBeenCalledWith(
      'notifications/read',
      expect.anything()
    );
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_lead_dossie',
      params: { leadId: 40 },
    });
  });

  it('lead com conversa e notificação de conversa abrem a conversa', async () => {
    listaRef.value = [
      { ...avisoDoHub, primary_actor: { id: 40, conversation_id: 77 } },
      {
        id: 1,
        notification_type: 'conversation_assignment',
        primary_actor_type: 'Conversation',
        primary_actor_id: 900,
        primary_actor: { id: 12 },
        push_message_title: 'Conversa #12 atribuída a você',
        read_at: 1760900000,
      },
    ];
    const wrapper = montar();
    await wrapper.find('[data-testid="sino"]').trigger('click');
    await wrapper.findAll('[data-testid="sino-item"]')[0].trigger('click');
    expect(routerPush).toHaveBeenLastCalledWith({
      name: 'inbox_conversation',
      params: { conversation_id: 77 },
    });
    await wrapper.find('[data-testid="sino"]').trigger('click');
    await wrapper.findAll('[data-testid="sino-item"]')[1].trigger('click');
    expect(routerPush).toHaveBeenLastCalledWith({
      name: 'inbox_conversation',
      params: { conversation_id: 12 },
    });
    // já lida: não chama a API de novo
    expect(NotificationsAPI.update).toHaveBeenCalledTimes(1);
  });

  it('notificação nova vira toast por 6 s e o clique abre', async () => {
    vi.useFakeTimers();
    const wrapper = montar();
    await flushPromises();
    emitter.emit(BUS_EVENTS.RAMON_NOTIFICACAO_NOVA, avisoDoHub);
    await flushPromises();
    expect(wrapper.find('[data-testid="sino-toast"]').text()).toContain(
      'Lead parado há 3 dias'
    );

    vi.advanceTimersByTime(6000);
    await flushPromises();
    expect(wrapper.find('[data-testid="sino-toast"]').exists()).toBe(false);

    emitter.emit(BUS_EVENTS.RAMON_NOTIFICACAO_NOVA, avisoDoHub);
    await flushPromises();
    await wrapper.find('[data-testid="sino-toast"]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_lead_dossie',
      params: { leadId: 40 },
    });
    expect(wrapper.find('[data-testid="sino-toast"]').exists()).toBe(false);
    wrapper.unmount();
    vi.useRealTimers();
  });
});
