import { mount, flushPromises } from '@vue/test-utils';
import EquipeNova1a1 from '../EquipeNova1a1.vue';
import EquipeAPI from 'dashboard/api/ramonEquipe';

const push = vi.hoisted(() => vi.fn());

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: getter =>
    ({
      'agents/getAgents': {
        value: [
          { id: 1, name: 'Eduardo Schlata', thumbnail: '' },
          { id: 20, name: 'Brenda Antunes', thumbnail: 'b.png' },
          { id: 30, name: 'Tamires de Farias', thumbnail: '' },
        ],
      },
      getCurrentUserID: { value: 1 },
      getCurrentAccountId: { value: 2 },
    })[getter],
}));
vi.mock('dashboard/api/ramonEquipe', () => ({
  default: { conversa: vi.fn() },
}));
vi.mock('dashboard/components-next/avatar/Avatar.vue', () => ({
  default: { props: ['name'], template: '<span />' },
}));

const montar = () =>
  mount(EquipeNova1a1, {
    props: { inboxId: 4 },
    global: { directives: { tooltip: {} } },
  });

const abrirMenu = async wrapper => {
  await wrapper.find('[data-testid="equipe-nova-1a1"]').trigger('click');
};

// Itens do DropdownMenu (a raiz dele tem z-50).
const itens = wrapper => wrapper.findAll('.z-50 button').map(b => b.text());

describe('EquipeNova1a1.vue', () => {
  beforeEach(() => vi.clearAllMocks());

  it('começa fechado e abre a lista de colegas sem a própria pessoa', async () => {
    const wrapper = montar();
    expect(itens(wrapper)).toEqual([]);
    await abrirMenu(wrapper);
    expect(itens(wrapper)).toEqual(['Brenda Antunes', 'Tamires de Farias']);
  });

  it('a busca filtra os colegas', async () => {
    const wrapper = montar();
    await abrirMenu(wrapper);
    await wrapper.find('input[type="search"]').setValue('tam');
    expect(itens(wrapper)).toEqual(['Tamires de Farias']);
  });

  it('escolher um colega abre a 1:1 e fecha o menu', async () => {
    EquipeAPI.conversa.mockResolvedValue({ data: { id: 99 } });
    const wrapper = montar();
    await abrirMenu(wrapper);
    const brenda = wrapper
      .findAll('.z-50 button')
      .find(b => b.text() === 'Brenda Antunes');
    await brenda.trigger('click');
    await flushPromises();
    expect(EquipeAPI.conversa).toHaveBeenCalledWith(20);
    expect(push).toHaveBeenCalledWith({
      name: 'conversation_through_inbox',
      params: { accountId: 2, inbox_id: 4, conversation_id: 99 },
    });
    expect(itens(wrapper)).toEqual([]);
  });
});
