import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import Playbooks from '../Playbooks.vue';

vi.mock('dashboard/api/roteiroPassos', () => ({
  default: {
    get: vi.fn(() =>
      Promise.resolve({
        data: {
          calculadoras: {},
          payload: [
            {
              id: 1,
              thesis_id: null,
              position: 0,
              chave: 'tem_advogado',
              titulo: 'Tem advogado',
              tipo_resposta: 'sim_nao',
              opcoes: [],
              calculadora: null,
              calculadora_campos: {},
              saidas: [],
            },
            {
              id: 2,
              thesis_id: 1,
              position: 0,
              chave: 'sequela',
              titulo: 'Sequela',
              tipo_resposta: 'texto',
              opcoes: [],
              calculadora: null,
              calculadora_campos: {},
              saidas: [],
            },
          ],
        },
      })
    ),
  },
}));

vi.mock('dashboard/api/leads', () => ({
  default: {
    zapsignTemplates: vi.fn(() =>
      Promise.resolve({
        data: [{ token: 'modelo-aa', name: 'Contrato auxílio-acidente' }],
      })
    ),
  },
}));

const theses = [
  {
    id: 1,
    name: 'Auxílio-acidente',
    active: true,
    position: 0,
    items: [
      { id: 11, section: 'abertura', title: 'A', content: 'a', position: 0 },
      { id: 12, section: 'objecao', title: 'O', content: 'o', position: 1 },
      { id: 13, section: 'abertura', title: 'B', content: 'b', position: 2 },
    ],
  },
  { id: 2, name: 'BPC/LOAS', active: false, position: 1 },
];

const buildStore = () =>
  createStore({
    modules: {
      theses: {
        namespaced: true,
        getters: {
          getTheses: () => theses,
          getThesis: () => id => theses.find(t => t.id === id),
          getUIFlags: () => ({ isFetching: false }),
        },
      },
    },
  });

const mountPlaybooks = () => {
  const store = buildStore();
  store.dispatch = vi.fn().mockResolvedValue({});
  const wrapper = mount(Playbooks, {
    global: { plugins: [store], mocks: { $t: k => k } },
  });
  return { wrapper, store };
};

describe('Playbooks.vue', () => {
  it('renders the thesis list from the store', () => {
    const { wrapper } = mountPlaybooks();
    const items = wrapper.findAll('[data-testid="playbooks-item"]');
    expect(items).toHaveLength(2);
    expect(wrapper.text()).toContain('Auxílio-acidente');
    expect(wrapper.text()).toContain('BPC/LOAS');
  });

  it('fetches theses on mount', () => {
    const { store } = mountPlaybooks();
    expect(store.dispatch).toHaveBeenCalledWith('theses/get');
  });

  it('dispatches theses/create when adding a new thesis', async () => {
    const { wrapper, store } = mountPlaybooks();
    await wrapper
      .find('[data-testid="playbooks-add-input"]')
      .setValue('Trabalhista');
    await wrapper.find('[data-testid="playbooks-add-button"]').trigger('click');
    expect(store.dispatch).toHaveBeenCalledWith('theses/create', {
      name: 'Trabalhista',
    });
  });

  it('salva mínimo, base e "na tabela" da tese', async () => {
    const { wrapper, store } = mountPlaybooks();
    await wrapper.findAll('[data-testid="playbooks-item"]')[0].trigger('click');
    await wrapper
      .find('[data-testid="playbooks-honorario-na-tabela"]')
      .setValue(true);
    await wrapper
      .find('[data-testid="playbooks-honorario-minimo-qtd-input"]')
      .setValue('3');
    await wrapper
      .find('[data-testid="playbooks-honorario-minimo-base"]')
      .setValue('sm');
    expect(store.dispatch).toHaveBeenLastCalledWith(
      'theses/update',
      expect.objectContaining({
        id: 1,
        honorario_minimo_qtd: 3,
        honorario_minimo_base: 'sm',
        honorario_na_tabela: true,
      })
    );
  });

  it('shows the empty detail state when no thesis is selected', () => {
    const { wrapper } = mountPlaybooks();
    expect(
      wrapper.find('[data-testid="playbooks-empty-detail"]').exists()
    ).toBe(true);
  });

  it('desce um item dentro da seção mandando a ordem da tese inteira', async () => {
    const { wrapper, store } = mountPlaybooks();
    await wrapper.findAll('[data-testid="playbooks-item"]')[0].trigger('click');
    const rows = wrapper.findAll('[data-testid="playbooks-item-row"]');
    expect(
      rows[0].find('[data-testid="playbooks-item-move-up"]').attributes()
    ).toHaveProperty('disabled');
    await rows[0]
      .find('[data-testid="playbooks-item-move-down"]')
      .trigger('click');
    expect(store.dispatch).toHaveBeenCalledWith('theses/reorderItems', {
      thesisId: 1,
      ids: [13, 12, 11],
    });
  });
  it('tese com leads: oferece desativar em vez de excluir', async () => {
    const { wrapper, store } = mountPlaybooks();
    store.dispatch.mockImplementation(action =>
      action === 'theses/delete'
        ? Promise.reject(
            Object.assign(new Error('422'), {
              response: { data: { leads_count: 3 } },
            })
          )
        : Promise.resolve({})
    );
    await wrapper
      .findAll('[data-testid="playbooks-item-remove"]')[0]
      .trigger('click');
    await wrapper
      .find('[data-testid="confirm-modal-confirm"]')
      .trigger('click');
    await flushPromises();
    expect(
      wrapper.find('[data-testid="playbooks-thesis-in-use"]').exists()
    ).toBe(true);
    await wrapper
      .find('[data-testid="confirm-modal-confirm"]')
      .trigger('click');
    expect(store.dispatch).toHaveBeenCalledWith('theses/update', {
      id: 1,
      active: false,
    });
  });

  it('mostra os passos comuns no topo', async () => {
    const { wrapper } = mountPlaybooks();
    await flushPromises();
    const comuns = wrapper.find('[data-testid="roteiro-comuns"]');
    expect(comuns.text()).toContain('Tem advogado');
    expect(comuns.text()).not.toContain('Sequela');
  });

  it('aba Roteiro da IA mostra só os passos da tese', async () => {
    const { wrapper } = mountPlaybooks();
    await flushPromises();
    await wrapper.findAll('[data-testid="playbooks-item"]')[0].trigger('click');
    await wrapper
      .find('[data-testid="playbooks-aba-roteiro"]')
      .trigger('click');
    const passos = wrapper.findAll(
      '[data-testid="playbooks-roteiro"] [data-testid="roteiro-passo-abrir"]'
    );
    expect(passos.map(p => p.text())).toEqual(['Sequela']);
    expect(wrapper.find('[data-testid="playbooks-section"]').exists()).toBe(
      false
    );
  });

  it('salva as palavras-chave como lista', async () => {
    const { wrapper, store } = mountPlaybooks();
    await wrapper.findAll('[data-testid="playbooks-item"]')[0].trigger('click');
    const campo = wrapper.find(
      '[data-testid="playbooks-palavras-chave-input"]'
    );
    await campo.setValue('acidente, sequela ');
    await campo.trigger('blur');
    expect(store.dispatch).toHaveBeenLastCalledWith(
      'theses/update',
      expect.objectContaining({
        id: 1,
        palavras_chave: ['acidente', 'sequela'],
      })
    );
  });

  it('escolhe o modelo de contrato do ZapSign da tese', async () => {
    const { wrapper, store } = mountPlaybooks();
    await flushPromises();
    await wrapper.findAll('[data-testid="playbooks-item"]')[0].trigger('click');
    const campo = wrapper.find('[data-testid="playbooks-zapsign-modelo"]');
    expect(campo.text()).toContain('Contrato auxílio-acidente');

    await campo.setValue('modelo-aa');
    expect(store.dispatch).toHaveBeenLastCalledWith(
      'theses/update',
      expect.objectContaining({ id: 1, zapsign_template_id: 'modelo-aa' })
    );
  });
});
