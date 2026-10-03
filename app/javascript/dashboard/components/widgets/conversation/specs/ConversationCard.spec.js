import { shallowMount } from '@vue/test-utils';
import ConversationCard from '../ConversationCard.vue';

const agora = Math.floor(Date.now() / 1000);
const inboxDeLead = { id: 1, auto_create_lead: true };

const montar = (chat = {}, inbox = inboxDeLead) =>
  shallowMount(ConversationCard, {
    props: {
      chat: {
        id: 7,
        created_at: agora - 60,
        timestamp: agora - 60,
        first_reply_created_at: 0,
        unread_count: 1,
        labels: ['fase-novo', 'vip'],
        messages: [],
        ramon_lead: {
          id: 3,
          stage_name: 'Novo',
          stage_color: '#475569',
          thesis_name: 'BPC/LOAS',
        },
        ...chat,
      },
      currentContact: { name: 'Rosane Fagundes' },
      inbox,
    },
    global: { mocks: { $t: k => k } },
  });

describe('ConversationCard (redesign v2)', () => {
  it('mostra a etiqueta da etapa, a tese e o selo do prazo', () => {
    const wrapper = montar();
    expect(wrapper.find('.ramon-stage-pill').text()).toBe('Novo');
    expect(wrapper.text()).toContain('BPC/LOAS');
    expect(wrapper.findComponent({ name: 'SeloPrazo' }).exists()).toBe(true);
    expect(wrapper.findComponent({ name: 'TimeAgo' }).exists()).toBe(false);
  });

  it('respondida → sem selo, mostra a hora', () => {
    const wrapper = montar({ first_reply_created_at: agora - 30 });
    expect(wrapper.findComponent({ name: 'SeloPrazo' }).exists()).toBe(false);
    expect(wrapper.findComponent({ name: 'TimeAgo' }).exists()).toBe(true);
  });

  it('sem lead (caixa do escritório) → sem etiqueta e sem selo', () => {
    const wrapper = montar({ ramon_lead: null }, { id: 2 });
    expect(wrapper.find('.ramon-stage-pill').exists()).toBe(false);
    expect(wrapper.findComponent({ name: 'SeloPrazo' }).exists()).toBe(false);
  });

  it('etiqueta fase-* não vai pro CardLabels', () => {
    const wrapper = montar();
    expect(
      wrapper.findComponent({ name: 'CardLabels' }).props('conversationLabels')
    ).toEqual(['vip']);
  });

  it('não lida → bolinha azul; hover → checkbox da multi-seleção', async () => {
    const wrapper = montar();
    expect(wrapper.find('.bg-n-blue-9.rounded-full').exists()).toBe(true);
    await wrapper.trigger('mouseenter');
    expect(wrapper.findComponent({ name: 'Checkbox' }).exists()).toBe(true);
  });
});
