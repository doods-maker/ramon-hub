import { mount, flushPromises } from '@vue/test-utils';
import LinhaDaVida from '../LinhaDaVida.vue';
import LinhaDaVidaAPI from 'dashboard/api/linhaDaVida';
import ContactAPI from 'dashboard/api/contacts';

const route = { params: { accountId: '1' } };
vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('dashboard/api/linhaDaVida', () => ({ default: { show: vi.fn() } }));
vi.mock('dashboard/api/contacts', () => ({ default: { search: vi.fn() } }));

const montar = async () => {
  const wrapper = mount(LinhaDaVida, {
    global: { mocks: { $t: key => key }, stubs: { RouterLink: true } },
  });
  await flushPromises();
  return wrapper;
};

describe('LinhaDaVida.vue', () => {
  afterEach(() => {
    route.params = { accountId: '1' };
    vi.useRealTimers();
  });

  it('busca com erro mostra o erro com tentar de novo, não "ninguém encontrado"', async () => {
    vi.useFakeTimers();
    ContactAPI.search.mockRejectedValueOnce(new Error('rede'));
    const wrapper = await montar();

    await wrapper.find('[data-testid="pessoa-search"]').setValue('João');
    vi.advanceTimersByTime(300);
    await flushPromises();

    expect(wrapper.find('[data-testid="pessoa-search-error"]').exists()).toBe(
      true
    );
    expect(wrapper.text()).not.toContain('RAMON.LINHA_DA_VIDA.SEARCH_EMPTY');

    ContactAPI.search.mockResolvedValueOnce({
      data: { payload: [{ id: 9, name: 'João' }] },
    });
    await wrapper.find('[data-testid="pessoa-search-retry"]').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[data-testid="pessoa-result"]')).toHaveLength(1);
  });

  it('caso fechado com prescrição correndo mostra o chip do painel', async () => {
    route.params = { accountId: '1', contactId: '9' };
    LinhaDaVidaAPI.show.mockResolvedValue({
      data: {
        contact: { id: 9, name: 'João' },
        marcos: [],
        leads: [
          {
            id: 5,
            name: 'João — perdido',
            is_lost: true,
            lost_at: '2022-10-06',
            prescription: { lost_installments: 4 },
            benefit_monthly_value: null,
          },
        ],
      },
    });
    const wrapper = await montar();

    expect(
      wrapper
        .find(
          '[data-testid="lifeline-past"] [data-testid="lifeline-prescricao"]'
        )
        .text()
    ).toBe('RAMON.KANBAN.CARD.PRESCRIPTION_LOST');
  });
});
