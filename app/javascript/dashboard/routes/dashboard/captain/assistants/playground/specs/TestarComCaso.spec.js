import { mount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import TestarComCaso from '../TestarComCaso.vue';

vi.mock('dashboard/api/leads', () => ({ default: { get: vi.fn() } }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('@vueuse/core', async importOriginal => ({
  ...(await importOriginal()),
  useDebounceFn: fn => fn,
}));

describe('TestarComCaso (I-PG4)', () => {
  it('busca pelo nome e devolve o lead escolhido; limpa a busca', async () => {
    LeadsAPI.get.mockResolvedValue({
      data: { payload: [{ id: 12, name: 'Maria Souza' }] },
    });
    const wrapper = mount(TestarComCaso);
    await wrapper.find('[data-testid="testar-caso-busca"]').setValue('mar');
    await flushPromises();
    expect(LeadsAPI.get).toHaveBeenCalledWith({ q: 'mar' });
    await wrapper.find('[data-testid="testar-caso-opcao"]').trigger('click');
    expect(wrapper.emitted('escolher')[0][0]).toEqual({
      id: 12,
      name: 'Maria Souza',
    });
    expect(wrapper.find('[data-testid="testar-caso-opcao"]').exists()).toBe(
      false
    );
  });

  it('menos de 2 letras não busca', async () => {
    LeadsAPI.get.mockClear();
    const wrapper = mount(TestarComCaso);
    await wrapper.find('[data-testid="testar-caso-busca"]').setValue('m');
    await flushPromises();
    expect(LeadsAPI.get).not.toHaveBeenCalled();
  });
});
