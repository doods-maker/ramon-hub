import { shallowMount } from '@vue/test-utils';
import LeadCard from '../LeadCard.vue';

const lead = {
  id: 10,
  name: 'João',
  conversation_id: 99,
  stage_name: 'Negociação',
  stage_color: '#f59e0b',
  benefit_type_name: 'Auxílio-acidente',
  lead_priority_name: 'Alta',
  value: '12000.50',
  closer_name: 'Eduardo Schlata',
};

const mountCard = (props = {}) =>
  shallowMount(LeadCard, {
    props: { lead, ...props },
    global: { mocks: { $t: k => k } },
  });

describe('LeadCard.vue', () => {
  it('renderiza nome, benefício e valor formatado em BRL', () => {
    const wrapper = mountCard();
    expect(wrapper.text()).toContain('João');
    expect(wrapper.text()).toContain('Auxílio-acidente');
    expect(wrapper.text()).toContain('12.000,50');
  });

  it('aplica a cor da etapa no chip', () => {
    const wrapper = mountCard();
    const chip = wrapper.find('[data-testid="stage-chip"]');
    expect(chip.attributes('style')).toContain('rgb(245, 158, 11)');
  });

  it('emite open-lead ao clicar no corpo', async () => {
    const wrapper = mountCard();
    await wrapper.find('[data-testid="lead-card-body"]').trigger('click');
    expect(wrapper.emitted('openLead')[0][0]).toEqual(lead);
  });

  it('shows a labeled "open conversation" button in the footer only with conversation_id', () => {
    const wrapper = mountCard({ lead: { ...lead, conversation_id: 99 } });
    const btn = wrapper.find('[data-testid="open-conversation"]');
    expect(btn.exists()).toBe(true);
    expect(btn.text()).toContain('RAMON.FUNIL.OPEN_CONVERSATION');
  });

  it('emits open-conversation with the id and does not open the lead', async () => {
    const wrapper = mountCard({ lead: { ...lead, conversation_id: 99 } });
    await wrapper.find('[data-testid="open-conversation"]').trigger('click');
    expect(wrapper.emitted('openConversation')[0]).toEqual([99]);
    expect(wrapper.emitted('openLead')).toBeFalsy();
  });

  it('hides the button without conversation_id', () => {
    const wrapper = mountCard({ lead: { ...lead, conversation_id: null } });
    expect(wrapper.find('[data-testid="open-conversation"]').exists()).toBe(
      false
    );
  });
});
