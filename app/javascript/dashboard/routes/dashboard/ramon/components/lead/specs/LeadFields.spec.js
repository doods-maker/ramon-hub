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
          getStages: () => [{ id: 1, name: 'Novo' }],
          getBenefitTypes: () => [],
          getPriorities: () => [],
        },
      },
      agents: { namespaced: true, getters: { getAgents: () => [] } },
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
    const createNote = vi
      .fn()
      .mockResolvedValue({
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
});
