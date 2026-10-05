import { mount, flushPromises } from '@vue/test-utils';
import LeadNotes from '../LeadNotes.vue';
import LeadsAPI from 'dashboard/api/leads';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/leads', () => ({
  default: { getNotes: vi.fn(), createNote: vi.fn() },
}));
vi.mock('shared/helpers/mitt', () => ({ emitter: { emit: vi.fn() } }));

const RASCUNHO = 'RASCUNHO (revisar antes de enviar) — retomada nº 2:';

const note = (id, body) => ({
  id,
  body,
  author_name: 'Eduardo',
  created_at: '2026-07-23T12:00:00Z',
});

const mountNotes = (props = {}) =>
  mount(LeadNotes, {
    props: { leadId: 7, ...props },
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

  it('recarrega quando refreshKey muda (retomada gravou nota pelo backend)', async () => {
    LeadsAPI.getNotes.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountNotes();
    await flushPromises();
    LeadsAPI.getNotes.mockResolvedValue({
      data: { payload: [note(9, `${RASCUNHO}\nOi Maria`)] },
    });
    await wrapper.setProps({ refreshKey: '2026-10-05T12:00:00Z' });
    await flushPromises();
    expect(LeadsAPI.getNotes).toHaveBeenCalledTimes(2);
    expect(wrapper.text()).toContain('Oi Maria');
  });

  describe('Usar no editor (nota RASCUNHO)', () => {
    beforeEach(() => {
      LeadsAPI.getNotes.mockResolvedValue({
        data: {
          payload: [
            note(1, 'Perícia remarcada'),
            note(2, `${RASCUNHO}\nOi Maria, tudo bem?\nConseguiu o laudo?`),
          ],
        },
      });
    });

    it('na conversa: insere no editor só o texto, sem o cabeçalho', async () => {
      const wrapper = mountNotes({ inConversation: true });
      await flushPromises();
      const botoes = wrapper.findAll('[data-testid="lead-note-usar-editor"]');
      expect(botoes).toHaveLength(1);
      await botoes[0].trigger('click');
      expect(emitter.emit).toHaveBeenCalledWith(
        BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR,
        'Oi Maria, tudo bem?\nConseguiu o laudo?'
      );
    });

    it('fora da conversa (gaveta do Funil): sem botão', async () => {
      const wrapper = mountNotes();
      await flushPromises();
      expect(
        wrapper.find('[data-testid="lead-note-usar-editor"]').exists()
      ).toBe(false);
    });
  });
});
