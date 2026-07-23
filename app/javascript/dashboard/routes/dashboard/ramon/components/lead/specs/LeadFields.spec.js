import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadFields from '../LeadFields.vue';
import LostReasonModal from '../../kanban/LostReasonModal.vue';
import LeadsAPI from 'dashboard/api/leads';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

vi.mock('dashboard/api/leads', () => ({
  default: { portalLink: vi.fn() },
}));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(),
}));

const lead = {
  id: 3,
  name: 'Ana',
  lead_stage_id: 1,
  value: 100,
  source: 'ig',
  notes: 'x',
  benefit_type_id: null,
  lead_priority_id: null,
  sdr_id: null,
  closer_id: null,
  contact_name: 'Ana',
  contact_phone: '+55',
  contact_email: null,
};

const build = (
  updateSpy = vi.fn(),
  fetchNotesSpy = vi.fn().mockResolvedValue([]),
  createNoteSpy = vi.fn().mockResolvedValue({})
) =>
  createStore({
    modules: {
      leads: {
        namespaced: true,
        actions: {
          update: updateSpy,
          fetchNotes: fetchNotesSpy,
          createNote: createNoteSpy,
        },
      },
      leadConfig: {
        namespaced: true,
        getters: {
          getStages: () => [
            { id: 1, name: 'Novo' },
            { id: 2, name: 'Fechado', is_won: true },
            { id: 3, name: 'Perdido', is_lost: true },
          ],
          getBenefitTypes: () => [],
          getPriorities: () => [],
          getChannels: () => [],
          getLostReasons: () => [],
        },
      },
      agents: { namespaced: true, getters: { getAgents: () => [] } },
      theses: {
        namespaced: true,
        getters: {
          getTheses: () => [{ id: 9, name: 'Auxílio-acidente', active: true }],
        },
      },
    },
  });

const mountFields = (
  updateSpy = vi.fn(),
  fetchNotesSpy = vi.fn().mockResolvedValue([]),
  createNoteSpy = vi.fn().mockResolvedValue({})
) =>
  shallowMount(LeadFields, {
    props: { lead },
    global: {
      plugins: [build(updateSpy, fetchNotesSpy, createNoteSpy)],
      mocks: { $t: k => k },
    },
  });

describe('LeadFields.vue', () => {
  it('saves a text field on blur when changed', async () => {
    const update = vi.fn();
    const wrapper = mountFields(update);
    const input = wrapper.find('[data-testid="field-name"]');
    await input.setValue('Ana Maria');
    await input.trigger('blur');
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 3,
      name: 'Ana Maria',
    });
  });

  it('does not save a text field on blur when unchanged', async () => {
    const update = vi.fn();
    const wrapper = mountFields(update);
    await wrapper.find('[data-testid="field-name"]').trigger('blur');
    expect(update).not.toHaveBeenCalled();
  });

  it('saves the stage on change', async () => {
    const update = vi.fn();
    const wrapper = mountFields(update);
    const select = wrapper.find('[data-testid="field-stage"]');
    await select.setValue(1);
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 3,
      lead_stage_id: 1,
    });
  });

  it('saves the thesis on change', async () => {
    const update = vi.fn();
    const wrapper = mountFields(update);
    const select = wrapper.find('[data-testid="field-thesis"]');
    await select.setValue(9);
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 3,
      thesis_id: 9,
    });
  });

  it('shows read-only contact info', () => {
    const wrapper = mountFields();
    expect(wrapper.text()).toContain('Ana');
    expect(wrapper.text()).toContain('+55');
  });

  it('copies the contact phone', async () => {
    const wrapper = mountFields();
    expect(wrapper.find('[data-testid="contact-copy-phone"]').exists()).toBe(
      true
    );
  });

  it('shows wa.me link only when the lead has no conversation', () => {
    const withConv = shallowMount(LeadFields, {
      props: { lead: { ...lead, conversation_id: 77 } },
      global: { plugins: [build()], mocks: { $t: k => k } },
    });
    expect(withConv.find('[data-testid="contact-wa-me"]').exists()).toBe(false);

    const withoutConv = mountFields();
    const link = withoutConv.find('[data-testid="contact-wa-me"]');
    expect(link.exists()).toBe(true);
    expect(link.attributes('href')).toBe('https://wa.me/55');
  });

  it('loads notes on mount and adds a note', async () => {
    const fetchNotes = vi
      .fn()
      .mockResolvedValue([
        { id: 1, body: 'oi', author_name: 'Ana', created_at: 'x' },
      ]);
    const createNote = vi.fn().mockResolvedValue({
      id: 2,
      body: 'nova',
      author_name: 'Ana',
      created_at: 'y',
    });
    const wrapper = mountFields(vi.fn(), fetchNotes, createNote);
    await flushPromises();
    expect(fetchNotes).toHaveBeenCalledWith(expect.anything(), 3);
    expect(wrapper.findAll('[data-testid="note-item"]')).toHaveLength(1);

    await wrapper.find('[data-testid="note-input"]').setValue('nova');
    await wrapper.find('[data-testid="note-add"]').trigger('click');
    await flushPromises();
    expect(createNote).toHaveBeenCalledWith(expect.anything(), {
      leadId: 3,
      body: 'nova',
    });
  });

  it('parses BRL input on blur and saves a plain number', async () => {
    const update = vi.fn();
    const wrapper = mountFields(update);
    const input = wrapper.find('[data-testid="field-value"]');
    await input.setValue('1.234,56');
    await input.trigger('blur');
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 3,
      value: 1234.56,
    });
  });

  it('reverts invalid BRL input on blur without saving', async () => {
    const update = vi.fn();
    const wrapper = mountFields(update);
    const input = wrapper.find('[data-testid="field-value"]');
    await input.setValue('abc');
    await input.trigger('blur');
    expect(update).not.toHaveBeenCalled();
    expect(input.element.value).toContain('100');
  });

  it('shows the value formatted as BRL', () => {
    const wrapper = mountFields();
    const input = wrapper.find('[data-testid="field-value"]');
    expect(input.element.value).toContain('100');
    expect(input.element.value).toContain('R$');
  });

  it('prompts for value when moving to a won stage and lead has no value', async () => {
    const update = vi.fn();
    const wrapper = shallowMount(LeadFields, {
      props: { lead: { ...lead, value: null } },
      global: { plugins: [build(update)], mocks: { $t: k => k } },
    });
    await wrapper.find('[data-testid="field-stage"]').setValue(2);
    expect(update).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="stage-won-prompt"]').exists()).toBe(
      true
    );

    await wrapper.find('[data-testid="stage-won-value"]').setValue('2.500,00');
    await wrapper.find('[data-testid="stage-won-save"]').trigger('click');
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 3,
      lead_stage_id: 2,
      value: 2500,
    });
  });

  it('skips the value and still moves the stage', async () => {
    const update = vi.fn();
    const wrapper = shallowMount(LeadFields, {
      props: { lead: { ...lead, value: null } },
      global: { plugins: [build(update)], mocks: { $t: k => k } },
    });
    await wrapper.find('[data-testid="field-stage"]').setValue(2);
    await wrapper.find('[data-testid="stage-won-skip"]').trigger('click');
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 3,
      lead_stage_id: 2,
    });
  });

  it('does not prompt when the lead already has a value', async () => {
    const update = vi.fn();
    const wrapper = mountFields(update); // lead.value = 100
    await wrapper.find('[data-testid="field-stage"]').setValue(2);
    expect(wrapper.find('[data-testid="stage-won-prompt"]').exists()).toBe(
      false
    );
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 3,
      lead_stage_id: 2,
    });
  });

  it('closes the won prompt when switching to a lost stage', async () => {
    const update = vi.fn();
    const wrapper = shallowMount(LeadFields, {
      props: {
        lead: { ...structuredClone(lead), value: null, lost_reason: null },
      },
      global: { plugins: [build(update)], mocks: { $t: k => k } },
    });
    const select = wrapper.find('[data-testid="field-stage"]');
    await select.setValue(2);
    expect(wrapper.find('[data-testid="stage-won-prompt"]').exists()).toBe(
      true
    );

    await select.setValue(3);
    expect(wrapper.find('[data-testid="stage-won-prompt"]').exists()).toBe(
      false
    );
    expect(wrapper.findComponent(LostReasonModal).exists()).toBe(true);
  });

  describe('motivo de perda via LostReasonModal', () => {
    const mountLost = update =>
      shallowMount(LeadFields, {
        props: { lead: { ...structuredClone(lead), lost_reason: null } },
        global: { plugins: [build(update)], mocks: { $t: k => k } },
      });

    it('opens the modal on a lost stage without patching', async () => {
      const update = vi.fn();
      const wrapper = mountLost(update);
      await wrapper.find('[data-testid="field-stage"]').setValue(3);
      expect(update).not.toHaveBeenCalled();
      expect(wrapper.findComponent(LostReasonModal).exists()).toBe(true);
    });

    it('patches stage + lost_reason when the modal confirms', async () => {
      const update = vi.fn();
      const wrapper = mountLost(update);
      await wrapper.find('[data-testid="field-stage"]').setValue(3);
      wrapper
        .findComponent(LostReasonModal)
        .vm.$emit('confirmMove', { lostReason: 'Sem retorno' });
      await flushPromises();
      expect(update).toHaveBeenCalledWith(expect.anything(), {
        id: 3,
        lead_stage_id: 3,
        lost_reason: 'Sem retorno',
      });
      expect(wrapper.findComponent(LostReasonModal).exists()).toBe(false);
    });

    it('restores the select and skips the patch when the modal cancels', async () => {
      const update = vi.fn();
      const wrapper = mountLost(update);
      const select = wrapper.find('[data-testid="field-stage"]');
      await select.setValue(3);
      wrapper.findComponent(LostReasonModal).vm.$emit('cancelMove');
      await flushPromises();
      expect(update).not.toHaveBeenCalled();
      expect(wrapper.findComponent(LostReasonModal).exists()).toBe(false);
      expect(select.element.value).toBe('1');
    });
  });

  describe('NPS pós-ganho', () => {
    const wonLead = {
      ...structuredClone(lead),
      won_at: '2026-07-20T12:00:00Z',
    };
    const mountWon = (update, extra = {}) =>
      shallowMount(LeadFields, {
        props: { lead: { ...wonLead, ...extra } },
        global: { plugins: [build(update)], mocks: { $t: k => k } },
      });

    it('hides the NPS input without won_at', () => {
      const wrapper = mountFields();
      expect(wrapper.find('[data-testid="field-nps"]').exists()).toBe(false);
    });

    it('saves the score under custom_attributes.nps on blur', async () => {
      const update = vi.fn();
      const wrapper = mountWon(update);
      const input = wrapper.find('[data-testid="field-nps"]');
      await input.setValue('9');
      await input.trigger('blur');
      expect(update).toHaveBeenCalledWith(expect.anything(), {
        id: 3,
        custom_attributes: {
          nps: { score: 9, em: expect.any(String) },
        },
      });
    });

    it('shows the stored score and reverts out-of-range input', async () => {
      const update = vi.fn();
      const wrapper = mountWon(update, {
        custom_attributes: { nps: { score: 7, em: '2026-07-21T10:00:00Z' } },
      });
      const input = wrapper.find('[data-testid="field-nps"]');
      expect(input.element.value).toBe('7');
      await input.setValue('11');
      await input.trigger('blur');
      expect(update).not.toHaveBeenCalled();
      expect(input.element.value).toBe('7');
    });
  });

  describe('template de nota rápida', () => {
    it('preenche o textarea ao escolher um template', async () => {
      const wrapper = mountFields();
      const select = wrapper.find('[data-testid="note-template-select"]');
      await select.setValue('TRIED_CONTACT');
      const textarea = wrapper.find('[data-testid="note-input"]');
      expect(textarea.element.value).toBe('Tried to contact — no answer.');
      // select resetou pro placeholder
      expect(select.element.value).toBe('');
    });

    it('anexa em nova linha quando o textarea já tem texto', async () => {
      const wrapper = mountFields();
      const textarea = wrapper.find('[data-testid="note-input"]');
      await textarea.setValue('já tinha isso');
      const select = wrapper.find('[data-testid="note-template-select"]');
      await select.setValue('MEETING_SCHEDULED');
      expect(textarea.element.value).toBe('já tinha isso\nMeeting scheduled.');
    });
  });

  describe('portal do cliente', () => {
    it('gera o link no backend e copia pro clipboard', async () => {
      LeadsAPI.portalLink.mockResolvedValue({
        data: { url: 'https://hub/portal/tok123' },
      });
      const wrapper = mountFields();
      await wrapper.find('[data-testid="portal-copy-link"]').trigger('click');
      await flushPromises();
      expect(LeadsAPI.portalLink).toHaveBeenCalledWith(3);
      expect(copyTextToClipboard).toHaveBeenCalledWith(
        'https://hub/portal/tok123'
      );
    });
  });

  describe('hint de lead sem tese', () => {
    it('mostra o hint quando thesis_id é null', () => {
      const wrapper = mountFields();
      expect(wrapper.find('[data-testid="no-thesis-hint"]').exists()).toBe(
        true
      );
    });

    it('esconde o hint quando o lead tem tese', () => {
      const update = vi.fn();
      const wrapper = shallowMount(LeadFields, {
        props: { lead: { ...lead, thesis_id: 9 } },
        global: { plugins: [build(update)], mocks: { $t: k => k } },
      });
      expect(wrapper.find('[data-testid="no-thesis-hint"]').exists()).toBe(
        false
      );
    });
  });
});
