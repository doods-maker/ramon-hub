import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadFields from '../LeadFields.vue';

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
          ],
          getBenefitTypes: () => [],
          getPriorities: () => [],
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
});
