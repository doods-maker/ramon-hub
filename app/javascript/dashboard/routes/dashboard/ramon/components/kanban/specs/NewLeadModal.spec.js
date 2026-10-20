import { mount, flushPromises } from '@vue/test-utils';
import NewLeadModal from '../NewLeadModal.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const mountModal = ({ theses } = {}) => {
  const dispatch = vi.fn().mockResolvedValue({ id: 99 });
  const store = {
    getters: {
      'leadConfig/getStages': [{ id: 1, name: 'Novo' }],
      'leadConfig/getPriorities': [],
      'leadConfig/getSources': [],
      'leadConfig/getChannels': [],
      'theses/getTheses': theses ?? [
        { id: 5, name: 'Auxílio-acidente (B36)', active: true },
        { id: 6, name: 'Tese antiga', active: false },
      ],
    },
    dispatch,
  };
  const wrapper = mount(NewLeadModal, {
    global: {
      mocks: { $t: k => k },
      plugins: [
        {
          install: app => {
            app.config.globalProperties.$store = store;
          },
        },
      ],
    },
  });
  return { wrapper, dispatch };
};

describe('NewLeadModal — tese', () => {
  it('lista as teses ativas com "Sem tese" por padrão', () => {
    const { wrapper } = mountModal();
    const options = wrapper.findAll('[data-testid="new-lead-thesis"] option');
    expect(options.map(o => o.text())).toEqual([
      'RAMON.FUNIL.NEW.NO_THESIS',
      'Auxílio-acidente (B36)',
    ]);
  });

  it('busca as teses quando a lista está vazia', () => {
    const { dispatch } = mountModal({ theses: [] });
    expect(dispatch).toHaveBeenCalledWith('theses/get');
  });

  it('envia thesis_id ao criar', async () => {
    const { wrapper, dispatch } = mountModal();
    await wrapper.find('[data-testid="new-lead-name"]').setValue('Maria');
    await wrapper.find('[data-testid="new-lead-thesis"]').setValue(5);
    await wrapper.find('[data-testid="new-lead-save"]').trigger('click');
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith(
      'leads/create',
      expect.objectContaining({ name: 'Maria', thesis_id: 5 })
    );
  });

  it('sem tese escolhida manda thesis_id null', async () => {
    const { wrapper, dispatch } = mountModal();
    await wrapper.find('[data-testid="new-lead-name"]').setValue('João');
    await wrapper.find('[data-testid="new-lead-save"]').trigger('click');
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith(
      'leads/create',
      expect.objectContaining({ thesis_id: null })
    );
  });
});
