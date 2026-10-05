import { mount, flushPromises } from '@vue/test-utils';
import LeadNotes from '../LeadNotes.vue';
import LeadsAPI from 'dashboard/api/leads';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/leads', () => ({
  default: { createNote: vi.fn() },
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
    global: { mocks: { $t: k => k } },
  });

describe('LeadNotes', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lista as notas recebidas do painel, a mais recente no topo', () => {
    const wrapper = mountNotes({
      notes: [note(1, 'Perícia remarcada'), note(2, 'Mandou o laudo')],
    });
    const notas = wrapper.findAll('[data-testid="lead-note"]');
    expect(notas).toHaveLength(2);
    expect(notas[0].text()).toContain('Mandou o laudo');
    expect(notas[1].text()).toContain('Perícia remarcada');
  });

  it('mostra o texto inteiro, sem cortar nem esconder notas', () => {
    const longa = `nota longa ${'x'.repeat(400)}`;
    const wrapper = mountNotes({
      notes: [longa, 2, 3, 4, 5, 6, 7].map((b, i) => note(i + 1, `${b}`)),
    });
    expect(wrapper.findAll('[data-testid="lead-note"]')).toHaveLength(7);
    expect(wrapper.text()).toContain(longa);
  });

  it('Salvar cria a nota, avisa o painel (created) e limpa o editor', async () => {
    LeadsAPI.createNote.mockResolvedValue({ data: note(2, 'Cliente ansiosa') });
    const wrapper = mountNotes();
    const input = wrapper.find('[data-testid="lead-note-input"]');
    expect(input.element.tagName).toBe('TEXTAREA');
    await input.setValue('Cliente ansiosa');
    await wrapper.find('[data-testid="lead-note-save"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.createNote).toHaveBeenCalledWith(7, 'Cliente ansiosa');
    expect(wrapper.emitted('created')[0]).toEqual([note(2, 'Cliente ansiosa')]);
    expect(input.element.value).toBe('');
  });

  it.each(['ctrl', 'meta'])(
    '%s+Enter salva; Enter sozinho não',
    async tecla => {
      LeadsAPI.createNote.mockResolvedValue({ data: note(3, 'a') });
      const wrapper = mountNotes();
      const input = wrapper.find('[data-testid="lead-note-input"]');
      await input.setValue('linha 1');
      await input.trigger('keydown.enter');
      expect(LeadsAPI.createNote).not.toHaveBeenCalled();
      await input.trigger(`keydown.enter.${tecla}`);
      await flushPromises();
      expect(LeadsAPI.createNote).toHaveBeenCalledWith(7, 'linha 1');
    }
  );

  it('template de nota rápida preenche o campo (e anexa ao que já tinha)', async () => {
    const wrapper = mountNotes();
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

  describe('Usar no editor (nota RASCUNHO)', () => {
    const notes = [
      note(1, 'Perícia remarcada'),
      note(2, `${RASCUNHO}\nOi Maria, tudo bem?\nConseguiu o laudo?`),
    ];

    it('na conversa: insere no editor só o texto, sem o cabeçalho', async () => {
      const wrapper = mountNotes({ inConversation: true, notes });
      const botoes = wrapper.findAll('[data-testid="lead-note-usar-editor"]');
      expect(botoes).toHaveLength(1);
      await botoes[0].trigger('click');
      expect(emitter.emit).toHaveBeenCalledWith(
        BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR,
        'Oi Maria, tudo bem?\nConseguiu o laudo?'
      );
    });

    it('fora da conversa (gaveta do Funil): sem botão', () => {
      const wrapper = mountNotes({ notes });
      expect(
        wrapper.find('[data-testid="lead-note-usar-editor"]').exists()
      ).toBe(false);
    });
  });
});
