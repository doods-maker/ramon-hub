import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConversationCard from '../ConversationCard.vue';

const agora = Math.floor(Date.now() / 1000);
const inboxDeLead = { id: 1, auto_create_lead: true };

const montar = (chat = {}, inbox = inboxDeLead, leadsDaStore = []) =>
  shallowMount(ConversationCard, {
    props: {
      chat: {
        id: 7,
        created_at: agora - 60,
        timestamp: agora - 60,
        first_reply_created_at: 0,
        status: 'open',
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
    global: {
      mocks: { $t: k => k },
      plugins: [
        createStore({
          modules: {
            leads: {
              namespaced: true,
              getters: {
                getLeadByConversationId: () => id =>
                  leadsDaStore.find(l => l.conversation_id === id),
              },
            },
          },
        }),
      ],
    },
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

  it('prefere o lead da store (etapa ao vivo pelo websocket)', () => {
    const wrapper = montar({}, inboxDeLead, [
      {
        id: 3,
        conversation_id: 7,
        stage_name: 'Reunião marcada',
        stage_color: '#6D28D9',
        thesis_name: 'BPC/LOAS',
      },
    ]);
    expect(wrapper.find('.ramon-stage-pill').text()).toBe('Reunião marcada');
  });

  it('conversa nova sem bloco slim usa o lead da store', () => {
    const wrapper = montar({ ramon_lead: null }, inboxDeLead, [
      { id: 9, conversation_id: 7, stage_name: 'Novo', thesis_name: null },
    ]);
    expect(wrapper.find('.ramon-stage-pill').text()).toBe('Novo');
  });

  it('lead da store de outra conversa (id diferente do slim) é ignorado', () => {
    const wrapper = montar({}, inboxDeLead, [
      { id: 99, conversation_id: 7, stage_name: 'Outro' },
    ]);
    expect(wrapper.find('.ramon-stage-pill').text()).toBe('Novo');
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
