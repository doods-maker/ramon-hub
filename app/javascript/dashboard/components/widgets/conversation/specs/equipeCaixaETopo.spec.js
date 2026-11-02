import { mount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import ConversationHeader from '../ConversationHeader.vue';
import MessagesView from '../MessagesView.vue';
import ReplyBox from '../ReplyBox.vue';
import { useEquipeStore } from 'dashboard/stores/equipe';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';

const estado = {
  equipe: true,
  digitando: [],
  meuId: 1,
};

vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => ({
    getters: {
      getSelectedChat: { id: 43, status: 'open' },
      getCurrentAccountId: 2,
      getCurrentUserID: estado.meuId,
      'contacts/getContact': () => ({ name: 'Contato', thumbnail: 'c.png' }),
      'inboxes/getInbox': id => ({ id, equipe: estado.equipe }),
      'inboxes/getInboxes': [{}, {}],
      'conversationTypingStatus/getUserList': () => estado.digitando,
    },
  }),
}));
vi.mock('vue-router', async original => ({
  ...(await original()),
  useRoute: () => ({ params: {}, name: 'inbox_conversation' }),
}));
vi.mock('vue-i18n', async original => ({
  ...(await original()),
  useI18n: () => ({
    t: (k, arg) => (typeof arg === 'number' ? `${k}:${arg}` : k),
  }),
}));
vi.mock('dashboard/composables/useInbox', () => ({
  useInbox: () => ({ isAWebWidgetInbox: { value: false } }),
}));

const STUBS = {
  Avatar: {
    name: 'AvatarFalso',
    props: ['name', 'src'],
    template: '<i />',
  },
  BackButton: true,
  InboxName: true,
  MoreActions: true,
  SLACardLabel: true,
  ConversationCallButton: true,
  LeadPanelToggle: true,
  IaDaConversa: true,
  FluentIcon: true,
};

const grupo = {
  id: 43,
  inbox_id: 7,
  equipe_tipo: 'grupo',
  equipe_pessoas: [],
  meta: { sender: { id: 5 } },
};
const direta = {
  ...grupo,
  id: 44,
  equipe_tipo: '1a1',
  equipe_pessoas: [
    { id: 1, name: 'Eu', thumbnail: '' },
    { id: 4, name: 'Brenda', thumbnail: 'b.png' },
  ],
};

const montarTopo = chat =>
  mount(ConversationHeader, {
    props: { chat },
    global: {
      stubs: STUBS,
      mocks: { $t: k => k },
      directives: { tooltip: {} },
    },
  });

describe('ConversationHeader', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    Object.assign(estado, { equipe: true, digitando: [], meuId: 1 });
  });

  it('grupo: nome do contato e "N participantes", sem ações de atendimento', () => {
    useEquipeStore().participantes[43] = [{ id: 1 }, { id: 2 }, { id: 3 }];
    const w = montarTopo(grupo);
    expect(w.text()).toContain('Contato');
    expect(w.text()).toContain('RAMON.EQUIPE.PARTICIPANTES:3');
    expect(w.text()).not.toContain('#43');
    ['MoreActions', 'LeadPanelToggle', 'IaDaConversa'].forEach(name => {
      expect(w.findComponent({ name }).exists()).toBe(false);
    });
    expect(w.findComponent({ name: 'ConversationCallButton' }).exists()).toBe(
      false
    );
  });

  it('digitando entra no lugar do subtítulo', () => {
    useEquipeStore().participantes[43] = [{ id: 1 }, { id: 2 }];
    estado.digitando = [{ id: 2, name: 'Gabriela' }];
    const w = montarTopo(grupo);
    expect(w.text()).toContain('TYPING.ONE');
    expect(w.text()).not.toContain('PARTICIPANTES');
  });

  it('1:1: foto e nome da outra pessoa, sem subtítulo', () => {
    const w = montarTopo(direta);
    const avatar = w.findComponent({ name: 'AvatarFalso' });
    expect(avatar.props()).toMatchObject({ name: 'Brenda', src: 'b.png' });
    expect(w.text()).toContain('Brenda');
    expect(w.text()).not.toContain('PARTICIPANTES');
  });

  it('admin de fora na 1:1 vê o contato', () => {
    estado.meuId = 99;
    const avatar = montarTopo(direta).findComponent({ name: 'AvatarFalso' });
    expect(avatar.props('name')).toBe('Contato');
  });

  it('fora da Equipe mantém #id e ações', () => {
    estado.equipe = false;
    const w = montarTopo({ ...grupo, equipe_tipo: undefined });
    expect(w.text()).toContain('#43');
    expect(w.findComponent({ name: 'MoreActions' }).exists()).toBe(true);
    expect(w.text()).toContain('Contato');
    expect(w.text()).not.toContain('PARTICIPANTES');
  });
});

describe('MessagesView: faixa de só leitura', () => {
  const soLeitura = over =>
    MessagesView.computed.equipeSoLeitura.call({
      equipe: true,
      equipeStore: { participantes: {} },
      currentChat: { id: 43 },
      currentUserId: 1,
      ...over,
    });

  it('não aparece enquanto a lista não carregou', () => {
    expect(soLeitura()).toBe(false);
  });

  it('aparece com a lista carregada e sem mim nela', () => {
    const equipeStore = { participantes: { 43: [{ id: 2 }] } };
    expect(soLeitura({ equipeStore })).toBe(true);
  });

  it('não aparece para quem participa', () => {
    const equipeStore = { participantes: { 43: [{ id: 1 }] } };
    expect(soLeitura({ equipeStore })).toBe(false);
  });

  it('não aparece fora da Equipe', () => {
    const equipeStore = { participantes: { 43: [{ id: 2 }] } };
    expect(soLeitura({ equipe: false, equipeStore })).toBe(false);
  });
});

describe('MessagesView: sugestão de etiquetas por IA', () => {
  const buscar = async equipe => {
    const ctx = {
      equipe,
      labelSuggestions: ['antiga'],
      isLabelSuggestionDismissed: () => false,
      currentChat: { id: 43, labels: [] },
      captainTasksEnabled: true,
      isLabelSuggestionFeatureEnabled: true,
      getLabelSuggestions: vi.fn(() => Promise.resolve(['nova'])),
      $nextTick: vi.fn(),
    };
    await MessagesView.methods.fetchSuggestions.call(ctx);
    return ctx;
  };

  it('na Equipe não chama a IA e limpa a lista', async () => {
    const ctx = await buscar(true);
    expect(ctx.getLabelSuggestions).not.toHaveBeenCalled();
    expect(ctx.labelSuggestions).toEqual([]);
  });

  it('fora da Equipe continua sugerindo', async () => {
    const ctx = await buscar(false);
    expect(ctx.getLabelSuggestions).toHaveBeenCalled();
    expect(ctx.labelSuggestions).toEqual(['nova']);
  });
});

describe('ReplyBox: tecla de envio', () => {
  const valido = (over, tecla) =>
    ReplyBox.methods.isAValidEvent.call(
      {
        equipe: false,
        isFocused: true,
        showUserMentions: false,
        showMentions: false,
        showCannedMenu: false,
        showVariablesMenu: false,
        isEditorHotKeyEnabled: k => k === 'cmd_enter',
        ...over,
      },
      tecla
    );

  it('Equipe: Enter envia, Cmd+Enter não, sem olhar a preferência', () => {
    expect(valido({ equipe: true }, 'enter')).toBe(true);
    expect(valido({ equipe: true }, 'cmd_enter')).toBe(false);
  });

  it('Equipe: Enter não envia com a lista do @ aberta', () => {
    expect(valido({ equipe: true, showUserMentions: true }, 'enter')).toBe(
      false
    );
  });

  it('fora da Equipe segue a preferência', () => {
    expect(valido({}, 'enter')).toBe(false);
    expect(valido({}, 'cmd_enter')).toBe(true);
  });

  it('Equipe nunca fica em nota privada; fora dela segue o modo', () => {
    const { isOnPrivateNote } = ReplyBox.computed;
    const replyType = REPLY_EDITOR_MODES.NOTE;
    expect(isOnPrivateNote.call({ equipe: true, replyType })).toBe(false);
    expect(isOnPrivateNote.call({ equipe: false, replyType })).toBe(true);
  });

  it('entrar na Equipe vindo de nota privada não muda o modo (rascunho da nota fica na nota)', () => {
    const ctx = {
      equipe: true,
      isOnPrivateNote: false,
      replyType: REPLY_EDITOR_MODES.NOTE,
      isAPIInbox: true,
      setCCAndToEmailsFromLastChat: vi.fn(),
      copilot: { reset: vi.fn() },
      fetchAndSetReplyTo: vi.fn(),
    };
    ReplyBox.watch.currentChat.call(ctx, { id: 2, can_reply: true }, { id: 1 });
    expect(ctx.replyType).toBe(REPLY_EDITOR_MODES.NOTE);
  });

  it('Equipe não envia com assinatura, mesmo com a preferência ligada', () => {
    const { sendWithSignature } = ReplyBox.computed;
    const ctx = {
      channelType: 'Channel::Api',
      fetchSignatureFlagFromUISettings: () => true,
    };
    expect(sendWithSignature.call({ ...ctx, equipe: true })).toBe(false);
    expect(sendWithSignature.call({ ...ctx, equipe: false })).toBe(true);
  });
});
