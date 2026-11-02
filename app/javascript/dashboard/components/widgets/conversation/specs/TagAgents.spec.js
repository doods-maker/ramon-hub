import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import TagAgents from '../TagAgents.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables/useKeyboardNavigableList', () => ({
  useKeyboardNavigableList: vi.fn(),
}));
vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({
    'agents/getVerifiedAgents': ref([{ id: 9, name: 'Agente', email: 'a@b' }]),
  }),
  useMapGetter: () => ref([{ id: 5, name: 'Time', description: 'd' }]),
}));

const ITENS = [
  { id: 0, name: 'todos', type: 'todos' },
  { id: 2, name: 'Ana', thumbnail: '', type: 'user' },
  { id: 3, name: 'Bia', thumbnail: '', type: 'user' },
];

const montar = props =>
  mount(TagAgents, {
    props,
    global: { stubs: { Avatar: true } },
  });

const nomes = w => w.findAll('h5').map(item => item.text());

describe('TagAgents', () => {
  it('com itens mostra só eles', () => {
    expect(nomes(montar({ itens: ITENS }))).toEqual(['todos', 'Ana', 'Bia']);
  });

  it('com itens filtra pela busca', () => {
    expect(nomes(montar({ itens: ITENS, searchKey: 'an' }))).toEqual(['Ana']);
  });

  it('com itens emite o item escolhido, inclusive @todos com id 0', async () => {
    const w = montar({ itens: ITENS });
    await w.findAll('[role="option"]')[0].trigger('click');
    expect(w.emitted('selectAgent')[0][0]).toMatchObject({
      id: 0,
      name: 'todos',
      type: 'todos',
    });
  });

  it('com itens, nomes na cor normal e altura para @todos + 5 pessoas', () => {
    const w = montar({ itens: ITENS });
    w.findAll('h5').forEach(nome => {
      expect(nome.classes()).toContain('text-n-slate-12');
    });
    expect(w.find('ul').classes()).toContain('max-h-[18rem]');
    expect(w.find('ul').classes()).not.toContain('max-h-[12.5rem]');
  });

  it('sem itens mantém a altura e o cinza de quem não está selecionado', () => {
    const w = montar({});
    expect(w.find('ul').classes()).toContain('max-h-[12.5rem]');
    expect(w.find('ul').classes()).not.toContain('max-h-[18rem]');
    expect(w.findAll('h5')[1].classes()).not.toContain('text-n-slate-12');
  });

  it('sem itens mantém agentes e times', () => {
    expect(nomes(montar({}))).toEqual(['Agente', 'Time']);
  });
});
