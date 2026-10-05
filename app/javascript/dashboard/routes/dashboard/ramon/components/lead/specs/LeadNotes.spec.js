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

  it('mostra as 5 últimas e "ver todas" abre o resto aqui mesmo, texto inteiro', async () => {
    const longa = `nota 1 ${'x'.repeat(200)}`;
    LeadsAPI.getNotes.mockResolvedValue({
      data: {
        payload: [longa, 2, 3, 4, 5, 6, 7].map((b, i) =>
          note(i + 1, i ? `nota ${b}` : b)
        ),
      },
    });
    const wrapper = mountNotes();
    await flushPromises();
    expect(wrapper.text()).not.toContain('nota 2');
    expect(wrapper.text()).toContain('nota 7');
    const verTodas = wrapper.find('[data-testid="lead-notes-ver-todas"]');
    expect(verTodas.text()).toBe('RAMON.LEAD_PANEL.NOTES.SHOW_ALL 7');
    await verTodas.trigger('click');
    expect(wrapper.text()).toContain('nota 2');
    expect(wrapper.text()).toContain(longa);
  });

  it('template de nota rápida preenche o campo (e anexa ao que já tinha)', async () => {
    LeadsAPI.getNotes.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountNotes();
    await flushPromises();
    const input = wrapper.find('[data-testid="lead-note-input"]');
    const select = wrapper.find('[data-testid="note-template-select"]');
    await select.setValue('TRIED_CONTACT');
    expect(input.element.value).toBe(
      'RAMON.DRAWER.NOTE_TEMPLATES.ITEMS.TRIED_CONTACT'
    );
    expect(select.element.value).toBe('');
    await input.setValue('Ligou');
    await select.setValue('AWAITING_DOCS');
    expect(input.element.value).toBe(
      'Ligou RAMON.DRAWER.NOTE_TEMPLATES.ITEMS.AWAITING_DOCS'
    );
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
