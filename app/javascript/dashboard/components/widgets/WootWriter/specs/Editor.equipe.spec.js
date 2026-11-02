import { nextTick, ref } from 'vue';
import { mount } from '@vue/test-utils';
import Editor from '../Editor.vue';

let view;
const preferencia = vi.fn();

vi.mock('@chatwoot/prosemirror-schema', async original => {
  const real = await original();
  return {
    ...real,
    EditorView: class extends real.EditorView {
      constructor(...args) {
        super(...args);
        view = this;
      }
    },
  };
});
vi.mock('dashboard/helper/editorHelper', async original => ({
  ...(await original()),
  scrollCursorIntoView: vi.fn(),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({
  useTrack: vi.fn(),
  useAlert: vi.fn(),
}));
vi.mock('dashboard/composables/emitter', () => ({ useEmitter: vi.fn() }));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));
vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({ captainTasksEnabled: ref(false) }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    isEditorHotKeyEnabled: preferencia,
    fetchSignatureFlagFromUISettings: () => false,
  }),
}));

const ITENS = [
  { id: 0, name: 'todos', type: 'todos' },
  { id: 2, name: 'Ana', type: 'user' },
];

const montar = props =>
  mount(Editor, {
    attachTo: document.body,
    props: {
      channelType: 'Channel::Api',
      enableVariables: true,
      focusOnMount: false,
      ...props,
    },
    global: {
      stubs: {
        TagAgents: true,
        CannedResponse: true,
        VariableList: true,
        KeyboardEmojiSelector: true,
        TagTools: true,
        CopilotMenuBar: true,
      },
    },
  });

const digitar = async texto => {
  view.dispatch(view.state.tr.insertText(texto));
  await nextTick();
};

const enter = () =>
  new KeyboardEvent('keydown', {
    key: 'Enter',
    code: 'Enter',
    keyCode: 13,
    bubbles: true,
    cancelable: true,
  });

const lista = w => w.findComponent({ name: 'TagAgents' });

describe('Editor na caixa Equipe', () => {
  let w;

  beforeEach(() => preferencia.mockReset());
  afterEach(() => w.unmount());

  it('abre a lista do @ em mensagem pública, com os itens recebidos', async () => {
    w = montar({ equipe: true, itensMarcacao: ITENS });
    await digitar('@');
    expect(lista(w).exists()).toBe(true);
    expect(lista(w).props('itens')).toEqual(ITENS);
    expect(w.emitted('toggleUserMention').at(-1)).toEqual([true]);
  });

  it('marcar @todos gera exatamente o token, e o rascunho reabre igual', async () => {
    w = montar({ equipe: true, itensMarcacao: ITENS });
    await digitar('@');
    lista(w).vm.$emit('selectAgent', ITENS[0]);
    await nextTick();
    const conteudo = w.emitted('update:modelValue').at(-1)[0];
    expect(conteudo).toContain('[@todos](mention://todos/0/todos)');

    await w.setProps({ modelValue: `${conteudo}oi` });
    expect(view.state.doc.textContent).toContain('@todos');
    await digitar('!');
    expect(w.emitted('update:modelValue').at(-1)[0]).toContain(
      '[@todos](mention://todos/0/todos)'
    );
  });

  it('desliga / e {{', async () => {
    w = montar({ equipe: true, itensMarcacao: ITENS });
    await digitar('/');
    expect(w.findComponent({ name: 'CannedResponse' }).exists()).toBe(false);
    await digitar(' {{');
    expect(w.findComponent({ name: 'VariableList' }).exists()).toBe(false);
  });

  it('Enter envia mesmo com a preferência de Cmd+Enter, sem consultá-la', () => {
    preferencia.mockImplementation(tecla => tecla === 'cmd_enter');
    w = montar({ equipe: true });
    view.dom.dispatchEvent(enter());
    expect(view.state.doc.childCount).toBe(1);
    expect(preferencia).not.toHaveBeenCalled();
  });
});

describe('Editor fora da caixa Equipe', () => {
  let w;

  beforeEach(() => preferencia.mockReset());
  afterEach(() => w.unmount());

  it('mensagem pública não mostra a lista do @ nem liga o bloqueio do Enter', async () => {
    w = montar({});
    await digitar('@');
    expect(lista(w).exists()).toBe(false);
    expect(w.emitted('toggleUserMention').at(-1)).toEqual([false]);
  });

  it('nota privada mantém a lista nativa de agentes e times', async () => {
    w = montar({ isPrivate: true });
    await digitar('@');
    expect(lista(w).exists()).toBe(true);
    expect(lista(w).props('itens')).toBeFalsy();
    expect(w.emitted('toggleUserMention').at(-1)).toEqual([true]);
  });

  it('mantém as respostas prontas em mensagem pública', async () => {
    w = montar({});
    await digitar('/');
    expect(w.findComponent({ name: 'CannedResponse' }).exists()).toBe(true);
  });

  it('Enter segue a preferência da pessoa', () => {
    preferencia.mockImplementation(tecla => tecla === 'cmd_enter');
    w = montar({});
    view.dom.dispatchEvent(enter());
    expect(view.state.doc.childCount).toBe(2);
    expect(preferencia).toHaveBeenCalledWith('enter');
  });
});
