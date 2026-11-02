import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import Message from '../Message.vue';
import MessageMeta from '../MessageMeta.vue';
import { useEquipeStore } from 'dashboard/stores/equipe';

const CAIXA_EQUIPE = 7;
const CAIXA_CLIENTE = 8;
const EU = 1;
const COLEGA = 2;

const conversas = { 43: {} };
const papel = ref('agent');

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key =>
    ({
      'inboxes/getInbox': ref(id => ({ id, equipe: id === 7 })),
      getConversationById: ref(id => conversas[id]),
      getCurrentRole: papel,
      getSelectedChatAttachments: ref([]),
    })[key] ?? ref(null),
}));
vi.mock('dashboard/composables/useInbox', () => ({
  useInbox: () => new Proxy({}, { get: () => ref(false) }),
}));
vi.mock('dashboard/composables/useTranslations', () => ({
  useTranslations: () => ({
    hasTranslations: ref(false),
    translationContent: ref(''),
  }),
}));
vi.mock('dashboard/composables', () => ({ useTrack: vi.fn() }));
vi.mock('vue-router', () => ({ useRoute: () => ({ query: {} }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: s => s }),
}));
vi.mock('next/avatar/Avatar.vue', () => ({
  default: { name: 'AvatarFalso', render: () => null },
}));
vi.mock(
  'dashboard/modules/conversations/components/MessageContextMenu.vue',
  () => ({
    default: {
      name: 'MenuFalso',
      props: ['enabledOptions'],
      render: () => null,
    },
  })
);

const montar = (props = {}) =>
  mount(Message, {
    props: {
      id: 10,
      messageType: 1,
      status: 'sent',
      content: 'Oi',
      conversationId: 43,
      createdAt: 1732195656,
      currentUserId: EU,
      inboxId: CAIXA_EQUIPE,
      senderId: COLEGA,
      senderType: 'User',
      sender: { id: COLEGA, name: 'Brenda', thumbnail: '', type: 'user' },
      ...props,
    },
    global: {
      directives: { 'dompurify-html': () => {} },
      mocks: { $t: k => k },
    },
  });

const container = w => w.find('.message-bubble-container').classes();
const bolha = w => w.find('[data-bubble-name="text"]').classes().join(' ');
const minha = {
  senderId: EU,
  sender: { id: EU, name: 'Eduardo', thumbnail: '', type: 'user' },
};
const semAutor = { sender: null, senderId: null, senderType: null };
const menu = w =>
  w.findComponent({ name: 'MenuFalso' }).props('enabledOptions');
const participantes = lista => {
  useEquipeStore().participantes[43] = lista.map(id => ({ id }));
};

describe('Message na caixa Equipe', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    papel.value = 'agent';
    conversas[43] = { id: 43, equipe_tipo: 'grupo', equipe_pessoas: [] };
  });

  describe('lado e cor', () => {
    it('minha mensagem fica à direita, no verde', () => {
      const w = montar(minha);
      expect(container(w)).toContain('justify-end');
      expect(bolha(w)).toContain('ramon-enviada');
    });

    it('colega fica à esquerda, no cinza', () => {
      const w = montar();
      expect(container(w)).toContain('justify-start');
      expect(bolha(w)).toContain('bg-n-slate-4');
      expect(bolha(w)).not.toContain('ramon-enviada');
    });

    it('admin de fora vê os dois lados à esquerda', () => {
      const w1 = montar({ currentUserId: 99 });
      const w2 = montar({ ...minha, currentUserId: 99 });
      expect(container(w1)).toContain('justify-start');
      expect(container(w2)).toContain('justify-start');
    });

    it('em envio continua à direita, mesmo sem autor', () => {
      const w = montar({
        status: 'progress',
        senderId: null,
        senderType: null,
        sender: { name: 'Eduardo', thumbnail: '' },
      });
      expect(container(w)).toContain('justify-end');
      expect(bolha(w)).toContain('ramon-enviada');
    });

    it('sem autor gravado (usuário apagado) fica à esquerda, no cinza', () => {
      const w = montar(semAutor);
      expect(container(w)).toContain('justify-start');
      expect(bolha(w)).toContain('bg-n-slate-4');
    });

    it('falha local, ainda sem autor, continua à direita', () => {
      const w = montar({ ...semAutor, status: 'failed' });
      expect(container(w)).toContain('justify-end');
    });

    it('fora da Equipe, mensagem sem autor segue à direita', () => {
      const w = montar({ ...semAutor, inboxId: CAIXA_CLIENTE });
      expect(container(w)).toContain('justify-end');
    });

    it('fora da Equipe, agente segue à direita no verde', () => {
      const w = montar({ inboxId: CAIXA_CLIENTE });
      expect(container(w)).toContain('justify-end');
      expect(bolha(w)).toContain('ramon-enviada');
    });
  });

  describe('nome e foto', () => {
    const foto = w => w.findComponent({ name: 'AvatarFalso' }).exists();
    const nome = w => w.find('[data-testid="equipe-autor"]');

    it('grupo: nome na primeira do bloco', () => {
      expect(nome(montar({ primeiroDoAutor: true })).text()).toBe('Brenda');
      expect(nome(montar({ primeiroDoAutor: false })).exists()).toBe(false);
    });

    it('grupo: foto só na primeira do bloco, junto do nome', () => {
      const primeira = { primeiroDoAutor: true, groupWithNext: true };
      const ultima = { primeiroDoAutor: false, groupWithNext: false };
      expect(foto(montar(primeira))).toBe(true);
      expect(foto(montar(ultima))).toBe(false);
    });

    it('sem autor gravado: sem nome e sem a foto de bot', () => {
      const w = montar({ ...semAutor, primeiroDoAutor: true });
      expect(nome(w).exists()).toBe(false);
      expect(foto(w)).toBe(false);
    });

    it('fora da Equipe a foto segue a regra nativa', () => {
      const cliente = { ...minha, inboxId: CAIXA_CLIENTE };
      expect(foto(montar({ ...cliente, groupWithNext: false }))).toBe(true);
      expect(foto(montar({ ...cliente, groupWithNext: true }))).toBe(false);
    });

    it('minha mensagem não tem nome nem foto', () => {
      const w = montar({ ...minha, primeiroDoAutor: true });
      expect(nome(w).exists()).toBe(false);
      expect(foto(w)).toBe(false);
    });

    it('1:1 de quem participa não tem nome nem foto', () => {
      conversas[43] = {
        id: 43,
        equipe_tipo: '1a1',
        equipe_pessoas: [{ id: EU }, { id: COLEGA }],
      };
      const w = montar({ primeiroDoAutor: true });
      expect(nome(w).exists()).toBe(false);
      expect(foto(w)).toBe(false);
    });

    it('1:1 lida por admin de fora mostra nome e foto', () => {
      conversas[43] = {
        id: 43,
        equipe_tipo: '1a1',
        equipe_pessoas: [{ id: COLEGA }, { id: 3 }],
      };
      const w = montar({ currentUserId: 99, primeiroDoAutor: true });
      expect(nome(w).text()).toBe('Brenda');
      expect(foto(w)).toBe(true);
    });

    it('fora da Equipe não mostra o nome', () => {
      const w = montar({ inboxId: CAIXA_CLIENTE, primeiroDoAutor: true });
      expect(nome(w).exists()).toBe(false);
    });
  });

  describe('marcação', () => {
    const marcado = w => bolha(w).includes('shadow-[inset_3px');

    it('marca quem foi citado, com fileta', () => {
      const content = `[@Eduardo](mention://user/${EU}/Eduardo) chegou?`;
      expect(marcado(montar({ content }))).toBe(true);
      expect(marcado(montar({ content: 'sem marca' }))).toBe(false);
    });

    it('@todos marca o colega, mas não a própria mensagem', () => {
      const content = '[@todos](mention://todos/0/todos) reunião';
      expect(marcado(montar({ content }))).toBe(true);
      expect(marcado(montar({ ...minha, content }))).toBe(false);
    });

    it('@todos não marca admin de fora', () => {
      participantes([COLEGA, 3]);
      const content = '[@todos](mention://todos/0/todos) reunião';
      expect(marcado(montar({ content, currentUserId: 99 }))).toBe(false);
    });

    it('fora da Equipe não marca', () => {
      const content = `[@Eduardo](mention://user/${EU}/Eduardo) chegou?`;
      const w = montar({ content, inboxId: CAIXA_CLIENTE });
      expect(marcado(w)).toBe(false);
    });
  });

  describe('menu', () => {
    it('só copiar, responder e apagar', () => {
      expect(Object.keys(menu(montar(minha))).sort()).toEqual([
        'copy',
        'delete',
        'equipe',
        'replyTo',
      ]);
    });

    it('autor apaga, mesmo com a lista ainda sem carregar', () => {
      expect(menu(montar(minha)).delete).toBe(true);
    });

    it('colega não apaga', () => {
      participantes([EU, COLEGA]);
      expect(menu(montar()).delete).toBe(false);
    });

    it('admin que participa apaga a do colega', () => {
      papel.value = 'administrator';
      participantes([EU, COLEGA]);
      expect(menu(montar()).delete).toBe(true);
    });

    it('admin sem a lista carregada não apaga a do colega', () => {
      papel.value = 'administrator';
      expect(menu(montar()).delete).toBe(false);
    });

    it('admin de fora só copia', () => {
      papel.value = 'administrator';
      participantes([COLEGA, 3]);
      const w = montar({
        currentUserId: 99,
        inboxSupportsReplyTo: { outgoing: true },
      });
      expect(menu(w)).toEqual({
        equipe: true,
        copy: true,
        delete: false,
        replyTo: false,
      });
    });

    it('responder segue a caixa (Task 7)', () => {
      const w = montar({ inboxSupportsReplyTo: { outgoing: true } });
      expect(menu(w).replyTo).toBe(true);
    });

    it('sem nenhuma opção o menu nem monta', () => {
      participantes([COLEGA, 3]);
      const w = montar({
        content: null,
        currentUserId: 99,
        attachments: [{ id: 1, fileType: 'file', dataUrl: 'x.pdf' }],
      });
      expect(w.findComponent({ name: 'MenuFalso' }).exists()).toBe(false);
    });

    it('fora da Equipe o menu mantém as opções de atendimento', () => {
      const w = montar({ inboxId: CAIXA_CLIENTE });
      expect(menu(w).equipe).toBeUndefined();
      expect(menu(w)).toEqual(
        expect.objectContaining({
          copy: true,
          delete: true,
          cannedResponse: true,
          copyLink: true,
          translate: true,
        })
      );
    });
  });

  describe('hora na linha do texto', () => {
    const hora = w => w.findComponent(MessageMeta).classes();
    const anexo = { id: 1, fileType: 'file', dataUrl: 'x.pdf' };

    it('texto puro: hora sobre a última linha, com espaço reservado', () => {
      const w = montar();
      expect(hora(w)).toContain('absolute');
      expect(bolha(w)).toContain('relative');
      expect(bolha(w)).toContain('after:inline-block');
    });

    it('texto com anexo: hora abaixo, sem sobrepor o anexo', () => {
      const w = montar({ attachments: [anexo, { ...anexo, id: 2 }] });
      expect(hora(w)).not.toContain('absolute');
      expect(hora(w)).toContain('justify-end');
      expect(bolha(w)).not.toContain('after:inline-block');
    });

    it('fora da Equipe a hora segue abaixo do texto', () => {
      const w = montar({ inboxId: CAIXA_CLIENTE });
      expect(hora(w)).not.toContain('absolute');
      expect(hora(w)).toContain('mt-2');
      expect(bolha(w)).not.toContain('after:inline-block');
    });
  });

  it('hora em HH:mm, mesmo em ano anterior', () => {
    const w = montar({ createdAt: 1600000000 });
    expect(w.find('time').text()).toMatch(/^\d{2}:\d{2}$/);
  });

  it('fora da Equipe a hora segue no formato nativo', () => {
    const w = montar({ inboxId: CAIXA_CLIENTE });
    expect(w.find('time').text()).not.toMatch(/^\d{2}:\d{2}$/);
  });

  it('colega não mostra status de envio', () => {
    const status = w => w.findComponent({ name: 'MessageStatus' }).exists();
    expect(status(montar())).toBe(false);
    expect(status(montar(minha))).toBe(true);
  });
});
