import { mount } from '@vue/test-utils';
import ConversationCard from '../ConversationCard.vue';
import MessagePreview from '../MessagePreview.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: 1 }),
}));

const FLUENT = { name: 'FluentIcon', props: ['icon'], template: '<i />' };
const COMUM = {
  stubs: { 'fluent-icon': FLUENT },
  mocks: { $t: k => k },
};

describe('MessagePreview', () => {
  const previa = (message, equipe = { meuId: 1, tipo: 'grupo' }) =>
    mount(MessagePreview, {
      props: { message, equipe },
      global: COMUM,
    });
  const ana = { id: 2, name: 'Ana', type: 'user' };
  const eu = { id: 1, name: 'Eu', type: 'user' };

  it('grupo: mensagem de colega leva "Fulano:" e marcação como @Nome', () => {
    const w = previa({
      content: '[@Eu](mention://user/1/Eu) oi',
      sender: ana,
      message_type: 1,
    });
    expect(w.text()).toBe('Ana: @Eu oi');
  });

  it('minha mensagem leva "Você:" e sem ícone de tipo', () => {
    const w = previa({ content: 'fechado', sender: eu, message_type: 1 });
    expect(w.text()).toBe('RAMON.EQUIPE.VOCE: fechado');
    expect(w.findComponent(FLUENT).exists()).toBe(false);
  });

  it('1:1: mensagem da outra pessoa vai sem prefixo', () => {
    const w = previa(
      { content: 'oi', sender: ana, message_type: 1 },
      { meuId: 1, tipo: '1a1' }
    );
    expect(w.text()).toBe('oi');
  });

  it('só com anexo: prefixo, ícone e texto nativos, nunca vazio', () => {
    const w = previa({
      content: '',
      sender: ana,
      message_type: 1,
      attachments: [{ file_type: 'audio' }],
    });
    expect(w.text().replace(/\s+/g, ' ')).toBe(
      'Ana: CHAT_LIST.ATTACHMENTS.audio.CONTENT'
    );
    expect(w.findComponent(FLUENT).props('icon')).toBeTruthy();
  });

  it('apagada mostra o texto de apagada com o prefixo', () => {
    const w = previa({
      content: 'Esta mensagem foi excluída',
      content_attributes: { deleted: true },
      sender: ana,
      message_type: 1,
    });
    expect(w.text()).toBe('Ana: Esta mensagem foi excluída');
  });

  it('@todos nunca aparece cru', () => {
    const w = previa({
      content: '[@todos](mention://todos/0/todos) reunião',
      sender: ana,
      message_type: 1,
    });
    expect(w.text()).toBe('Ana: @todos reunião');
    expect(w.html()).not.toContain('mention://');
  });

  it('fora da Equipe: sem prefixo e com o ícone de tipo', () => {
    const w = mount(MessagePreview, {
      props: { message: { content: 'oi', sender: ana, message_type: 1 } },
      global: COMUM,
    });
    expect(w.text()).toBe('oi');
    expect(w.findComponent(FLUENT).props('icon')).toBe('arrow-reply');
  });
});

describe('ConversationCard', () => {
  const AVATAR = {
    name: 'AvatarFalso',
    props: ['name', 'src', 'size', 'roundedFull'],
    template: '<div><slot name="overlay" :size="size" /></div>',
  };
  const chatBase = {
    id: 43,
    inbox_id: 7,
    unread_count: 0,
    timestamp: 1,
    created_at: 1,
    priority: 'high',
    labels: ['tese-x'],
    messages: [{ id: 1, content: 'oi', message_type: 1, sender: { id: 2 } }],
    equipe_tipo: 'grupo',
    equipe_pessoas: [],
  };
  const direta = {
    ...chatBase,
    equipe_tipo: '1a1',
    equipe_pessoas: [
      { id: 1, name: 'Eu', thumbnail: '' },
      { id: 4, name: 'Brenda', thumbnail: 'b.png' },
    ],
  };
  const montar = (chat, equipe = true, props = {}) =>
    mount(ConversationCard, {
      props: {
        chat,
        currentContact: { name: 'Brenda e Eu', thumbnail: 'c.png' },
        inbox: { id: 7, equipe },
        assignee: { name: 'Fulano' },
        showAssignee: true,
        selected: true,
        ...props,
      },
      global: {
        mocks: { $t: k => k },
        stubs: {
          Avatar: AVATAR,
          'fluent-icon': FLUENT,
          TimeAgo: { name: 'TimeAgoFalso', template: '<span />' },
          InboxName: true,
          CardPriorityIcon: { name: 'Prioridade', template: '<i />' },
          LeadLinhaCard: { name: 'LinhaLead', template: '<i />' },
          CardLabels: { name: 'Etiquetas', template: '<i />' },
          Checkbox: { name: 'CaixaSelecao', template: '<i />' },
          UnreadBadge: {
            name: 'Contador',
            props: ['count'],
            template: '<b class="contador">{{ count }}</b>',
          },
        },
      },
    });
  const selo = w => w.find('[data-equipe-selo]');
  const ausentes = ['Prioridade', 'LinhaLead', 'Etiquetas', 'CaixaSelecao'];

  it('Equipe: foto redonda de 40, sem meta, lead, etiquetas e seleção', () => {
    const w = montar(chatBase);
    expect(w.findComponent({ name: 'AvatarFalso' }).props()).toMatchObject({
      size: 40,
      roundedFull: true,
      name: 'Brenda e Eu',
    });
    ausentes.forEach(name => {
      expect(w.findComponent({ name }).exists()).toBe(false);
    });
    expect(w.text()).not.toContain('Fulano');
  });

  it('1:1: nome e foto da outra pessoa', () => {
    const w = montar(direta);
    expect(w.findComponent({ name: 'AvatarFalso' }).props()).toMatchObject({
      name: 'Brenda',
      src: 'b.png',
    });
    expect(w.find('h4').text()).toBe('Brenda');
  });

  it('selo @ vem antes do contador', () => {
    const w = montar({ ...chatBase, unread_count: 3, equipe_marcado: true });
    const irmaos = [...selo(w).element.parentElement.children];
    expect(selo(w).text()).toBe('RAMON.EQUIPE.SELO_MARCACAO');
    expect(irmaos[0]).toBe(selo(w).element);
    expect(irmaos[1].className).toContain('contador');
  });

  it('sem marcação não tem selo, só o contador', () => {
    const w = montar({ ...chatBase, unread_count: 3 });
    expect(selo(w).exists()).toBe(false);
    expect(w.find('.contador').text()).toBe('3');
  });

  it('hora verde só com não lida', () => {
    const hora = chat =>
      montar(chat).findComponent({ name: 'TimeAgoFalso' }).classes();
    const verde = '!text-[rgb(var(--ramon-nao-lida-texto))]';
    expect(hora({ ...chatBase, unread_count: 1 })).toContain(verde);
    expect(hora(chatBase)).not.toContain(verde);
  });

  it('prévia recebe o contexto da Equipe', () => {
    const w = montar({ ...chatBase, equipe_tipo: '1a1' });
    expect(w.findComponent(MessagePreview).props('equipe')).toEqual({
      meuId: 1,
      tipo: '1a1',
    });
  });

  it('fora da Equipe tudo fica como era, mesmo com campos de Equipe', () => {
    const w = montar(
      { ...direta, unread_count: 1, equipe_marcado: true },
      false
    );
    expect(w.findComponent({ name: 'AvatarFalso' }).props()).toMatchObject({
      size: 32,
      name: 'Brenda e Eu',
      src: 'c.png',
    });
    ausentes.forEach(name => {
      expect(w.findComponent({ name }).exists()).toBe(true);
    });
    expect(w.text()).toContain('Fulano');
    expect(selo(w).exists()).toBe(false);
    expect(w.find('.contador').text()).toBe('1');
    expect(w.findComponent(MessagePreview).props('equipe')).toBe(null);
    expect(w.findComponent({ name: 'TimeAgoFalso' }).classes()).toEqual([]);
  });
});
