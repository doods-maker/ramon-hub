import { mount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import ConversationBox from '../ConversationBox.vue';
import ConversationHeader from '../ConversationHeader.vue';
import MessagesView from '../MessagesView.vue';
import ReplyBox from '../ReplyBox.vue';
import { useEquipeStore } from 'dashboard/stores/equipe';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import inboxMixin from 'shared/mixins/inboxMixin';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

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
    props: ['name', 'src', 'size', 'roundedFull'],
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
    expect(w.text()).toContain('TYPING.ONE…');
    expect(w.text()).not.toContain('PARTICIPANTES');
  });

  it('1:1: foto e nome da outra pessoa, sem subtítulo', () => {
    const w = montarTopo(direta);
    const avatar = w.findComponent({ name: 'AvatarFalso' });
    expect(avatar.props()).toMatchObject({ name: 'Brenda', src: 'b.png' });
    expect(w.text()).toContain('Brenda');
    expect(w.text()).not.toContain('PARTICIPANTES');
  });

  it('foto redonda de 40 px só na Equipe', () => {
    const avatar = w => w.findComponent({ name: 'AvatarFalso' }).props();
    expect(avatar(montarTopo(grupo))).toMatchObject({
      size: 40,
      roundedFull: true,
    });
    estado.equipe = false;
    expect(avatar(montarTopo(grupo))).toMatchObject({
      size: 32,
      roundedFull: false,
    });
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

describe('ConversationBox: Dashboard Apps', () => {
  const appsDaTela = equipe =>
    ConversationBox.computed.dashboardApps.call({
      appsDaConta: [{ id: 9 }],
      currentChat: { inbox_id: 7 },
      getInbox: id => ({ id, equipe }),
    });

  it('não abrem na Equipe: o frame receberia o contexto da conversa', () => {
    expect(appsDaTela(true)).toEqual([]);
  });

  it('seguem iguais em caixa comum', () => {
    expect(appsDaTela(false)).toEqual([{ id: 9 }]);
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

describe('MessagesView: marcar lida ao voltar para a aba', () => {
  const estadoDaAba = valor =>
    vi.spyOn(document, 'visibilityState', 'get').mockReturnValue(valor);
  const voltar = over => {
    const makeMessagesRead = vi.fn();
    MessagesView.methods.onVisibilityChange.call({
      equipe: true,
      makeMessagesRead,
      ...over,
    });
    return makeMessagesRead;
  };

  afterEach(() => vi.restoreAllMocks());

  it('na Equipe, marca quando a aba fica visível', () => {
    estadoDaAba('visible');
    expect(voltar()).toHaveBeenCalledTimes(1);
  });

  it('na Equipe, não marca quando a aba some', () => {
    estadoDaAba('hidden');
    expect(voltar()).not.toHaveBeenCalled();
  });

  it('fora da Equipe, a volta para a aba não marca nada', () => {
    estadoDaAba('visible');
    expect(voltar({ equipe: false })).not.toHaveBeenCalled();
  });

  it('o listener entra no mounted e sai em removeBusListeners', () => {
    const adiciona = vi.spyOn(document, 'addEventListener');
    const remove = vi.spyOn(document, 'removeEventListener');
    const onVisibilityChange = vi.fn();
    const ctx = {
      addScrollListener: vi.fn(),
      fetchAllAttachmentsFromCurrentChat: vi.fn(),
      fetchSuggestions: vi.fn(),
      onVisibilityChange,
    };
    MessagesView.mounted.call(ctx);
    expect(adiciona).toHaveBeenCalledWith(
      'visibilitychange',
      onVisibilityChange
    );
    MessagesView.methods.removeBusListeners.call(ctx);
    expect(remove).toHaveBeenCalledWith('visibilitychange', onVisibilityChange);
  });
});

describe('MessagesView: participantes na reconexão', () => {
  const reconectar = equipeConversaId => {
    const carregarParticipantes = vi.fn(() => Promise.resolve());
    MessagesView.methods.onWebsocketReconnect.call({
      equipeConversaId,
      equipeStore: { carregarParticipantes },
    });
    return carregarParticipantes;
  };

  it('na Equipe, recarrega os participantes da conversa aberta', () => {
    expect(reconectar(43)).toHaveBeenCalledWith(43);
  });

  it('fora da Equipe, não busca nada', () => {
    expect(reconectar(null)).not.toHaveBeenCalled();
  });

  it('falha na busca não vira erro solto', async () => {
    const carregarParticipantes = vi.fn(() => Promise.reject(new Error('x')));
    await expect(
      MessagesView.methods.onWebsocketReconnect.call({
        equipeConversaId: 43,
        equipeStore: { carregarParticipantes },
      })
    ).resolves.toBeUndefined();
  });

  it('assina no created e sai em removeBusListeners', () => {
    const onWebsocketReconnect = vi.fn();
    const ctx = { onScrollToMessage: vi.fn(), onWebsocketReconnect };
    MessagesView.created.call(ctx);
    emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT);
    expect(onWebsocketReconnect).toHaveBeenCalledTimes(1);

    MessagesView.methods.removeBusListeners.call({
      ...ctx,
      onVisibilityChange: vi.fn(),
    });
    emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT);
    expect(onWebsocketReconnect).toHaveBeenCalledTimes(1);
  });
});

describe('MessagesView: responder citando', () => {
  it('a caixa Equipe (Channel::Api) oferece responder em qualquer mensagem', () => {
    const inboxHasFeature = feature =>
      inboxMixin.methods.inboxHasFeature.call(
        { channelType: 'Channel::Api' },
        feature
      );
    expect(
      MessagesView.computed.inboxSupportsReplyTo.call({
        inboxHasFeature,
        is360DialogWhatsAppChannel: false,
      })
    ).toEqual({ incoming: true, outgoing: true });
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

  describe('citação com o modo NOTE guardado', () => {
    const CHAVE = LOCAL_STORAGE_KEYS.MESSAGE_REPLY_TO;
    const trocar = (over, novaConversa, antiga) => {
      const ctx = {
        replyType: REPLY_EDITOR_MODES.NOTE,
        isAPIInbox: true,
        setCCAndToEmailsFromLastChat: vi.fn(),
        copilot: { reset: vi.fn() },
        fetchAndSetReplyTo: ReplyBox.methods.fetchAndSetReplyTo,
        inReplyTo: { id: 10 },
        conversationId: novaConversa.id,
        currentChat: novaConversa,
        $store: {
          getters: { 'inboxes/getInbox': id => ({ equipe: id === 7 }) },
        },
        ...over,
      };
      ReplyBox.watch.currentChat.call(ctx, novaConversa, antiga);
      return ctx;
    };

    beforeEach(() => {
      LocalStorage.clearAll();
    });

    it('entrando na Equipe, a citação é a da conversa atual', () => {
      LocalStorage.updateJsonStore(CHAVE, 2, 20);
      const conversa = { id: 2, inbox_id: 7, messages: [{ id: 20 }] };
      const ctx = trocar({ equipe: true }, conversa, { id: 1, inbox_id: 3 });
      expect(ctx.inReplyTo).toEqual({ id: 20 });
      expect(ctx.replyType).toBe(REPLY_EDITOR_MODES.NOTE);
    });

    it('entrando na Equipe sem citação guardada, a antiga some', () => {
      const conversa = { id: 2, inbox_id: 7, messages: [{ id: 10 }] };
      const ctx = trocar({ equipe: true }, conversa, { id: 1, inbox_id: 3 });
      expect(ctx.inReplyTo).toBeUndefined();
    });

    it('saindo da Equipe, a citação dela não acompanha para a conversa do cliente', () => {
      const conversa = { id: 3, inbox_id: 3, messages: [] };
      const ctx = trocar({ equipe: false }, conversa, { id: 2, inbox_id: 7 });
      expect(ctx.inReplyTo).toBeUndefined();
    });

    it('entre conversas de clientes segue o nativo: não recarrega', () => {
      const conversa = { id: 3, inbox_id: 3, messages: [] };
      const ctx = trocar({ equipe: false }, conversa, { id: 1, inbox_id: 3 });
      expect(ctx.inReplyTo).toEqual({ id: 10 });
    });
  });

  it('Equipe mostra a citação na caixa de escrever e a envia como in_reply_to', () => {
    const inboxHasFeature = feature =>
      inboxMixin.methods.inboxHasFeature.call(
        { channelType: 'Channel::Api' },
        feature
      );
    const mostra = ReplyBox.computed.shouldShowReplyToMessage.call({
      inReplyTo: { id: 9 },
      isPrivate: false,
      inboxHasFeature,
      is360DialogWhatsAppChannel: false,
      copilot: { isActive: { value: false } },
    });
    expect(mostra).toBe(true);
    expect(
      ReplyBox.methods.setReplyToInPayload.call(
        { inReplyTo: { id: 9 } },
        { content: 'Oi' }
      )
    ).toEqual({ content: 'Oi', contentAttributes: { in_reply_to: 9 } });
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
