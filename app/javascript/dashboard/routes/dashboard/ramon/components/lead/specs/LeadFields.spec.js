import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadFields from '../LeadFields.vue';
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

const build = (updateSpy = vi.fn()) =>
  createStore({
    modules: {
      leads: {
        namespaced: true,
        actions: { update: updateSpy },
      },
      leadConfig: {
        namespaced: true,
        getters: {
          getStages: () => [
            { id: 1, name: 'Novo' },
            { id: 2, name: 'Fechado', is_won: true },
            { id: 3, name: 'Perdido', is_lost: true },
          ],
          getPriorities: () => [],
          getLostReasons: () => [],
        },
      },
      agents: { namespaced: true, getters: { getAgents: () => [] } },
    },
  });

const mountFields = (updateSpy = vi.fn()) =>
  shallowMount(LeadFields, {
    props: { lead },
    global: { plugins: [build(updateSpy)], mocks: { $t: k => k } },
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

  it('não repete o que o Resumo já edita (etapa, valor, caso, tarefas, notas, telefone)', () => {
    const wrapper = mountFields();
    [
      'field-stage',
      'field-value',
      'field-thesis',
      'field-channel',
      'field-dcb-em',
      'note-input',
      'contact-copy-phone',
      'lead-reuniao',
    ].forEach(id =>
      expect(wrapper.find(`[data-testid="${id}"]`).exists()).toBe(false)
    );
    // segue aqui o que só existe aqui
    expect(wrapper.find('[data-testid="field-source"]').exists()).toBe(true);
    expect(
      wrapper.find('[data-testid="field-benefit-monthly-value"]').exists()
    ).toBe(true);
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
});
