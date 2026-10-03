import { shallowMount } from '@vue/test-utils';
import Funil from '../Funil.vue';

const mockRoute = { query: {} };
const routerReplace = vi.fn();
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => mockRoute,
  useRouter: () => ({ replace: routerReplace }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useStoreGetters: () => ({ 'ramonDashboard/getData': { value: {} } }),
}));

describe('Funil.vue', () => {
  it('?novo=1 abre o modal e fechar limpa a URL', async () => {
    mockRoute.query = { novo: '1', filtro: 'pos_venda' };
    const wrapper = shallowMount(Funil);
    const modal = wrapper.findComponent({ name: 'NewLeadModal' });
    expect(modal.exists()).toBe(true);
    modal.vm.$emit('close');
    await wrapper.vm.$nextTick();
    expect(routerReplace).toHaveBeenCalledWith({
      query: { filtro: 'pos_venda', novo: undefined },
    });
    expect(wrapper.findComponent({ name: 'NewLeadModal' }).exists()).toBe(
      false
    );
  });
});
