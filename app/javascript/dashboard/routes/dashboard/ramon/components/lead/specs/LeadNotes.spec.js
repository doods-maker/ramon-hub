import { mount, flushPromises } from '@vue/test-utils';
import LeadNotes from '../LeadNotes.vue';
import LeadsAPI from 'dashboard/api/leads';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/leads', () => ({
  default: { getNotes: vi.fn(), createNote: vi.fn() },
}));

const note = (id, body) => ({
  id,
  body,
  author_name: 'Eduardo',
  created_at: '2026-07-23T12:00:00Z',
});

const mountNotes = () =>
  mount(LeadNotes, {
    props: { leadId: 7 },
    global: { mocks: { $t: (k, p) => (p ? `${k} ${p.count}` : k) } },
  });

describe('LeadNotes', () => {
  beforeEach(() => vi.clearAllMocks());

  it('carrega e lista as notas do lead', async () => {
    LeadsAPI.getNotes.mockResolvedValue({
      data: { payload: [note(1, 'Perícia remarcada')] },
    });
    const wrapper = mountNotes();
    await flushPromises();
    expect(LeadsAPI.getNotes).toHaveBeenCalledWith(7);
    expect(wrapper.text()).toContain('Perícia remarcada');
  });

  it('cria nota pelo Enter e adiciona à lista', async () => {
    LeadsAPI.getNotes.mockResolvedValue({ data: { payload: [] } });
    LeadsAPI.createNote.mockResolvedValue({ data: note(2, 'Cliente ansiosa') });
    const wrapper = mountNotes();
    await flushPromises();
    const input = wrapper.find('[data-testid="lead-note-input"]');
    await input.setValue('Cliente ansiosa');
    await input.trigger('keyup.enter');
    await flushPromises();
    expect(LeadsAPI.createNote).toHaveBeenCalledWith(7, 'Cliente ansiosa');
    expect(wrapper.text()).toContain('Cliente ansiosa');
    expect(input.element.value).toBe('');
  });

  it('mostra só as 5 últimas com contador das anteriores', async () => {
    LeadsAPI.getNotes.mockResolvedValue({
      data: { payload: [1, 2, 3, 4, 5, 6, 7].map(i => note(i, `nota ${i}`)) },
    });
    const wrapper = mountNotes();
    await flushPromises();
    expect(wrapper.text()).not.toContain('nota 2');
    expect(wrapper.text()).toContain('nota 7');
    expect(wrapper.text()).toContain('RAMON.LEAD_PANEL.NOTES.HIDDEN 2');
  });
});
