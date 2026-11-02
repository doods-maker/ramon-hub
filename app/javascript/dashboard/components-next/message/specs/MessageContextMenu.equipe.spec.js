import { mount } from '@vue/test-utils';
import MessageContextMenu from 'dashboard/modules/conversations/components/MessageContextMenu.vue';

const montar = enabledOptions =>
  mount(MessageContextMenu, {
    props: {
      enabledOptions,
      isOpen: true,
      hideButton: true,
      message: { id: 1, content: 'Oi', conversation_id: 43 },
    },
    global: {
      stubs: {
        ContextMenu: { template: '<div><slot /></div>' },
        VirarFaqMenuItem: true,
      },
      mocks: { $t: k => k, $store: { getters: {} } },
    },
  });

// Filhos visíveis, na ordem: "item", "hr". O CSS do menu esconde o <hr> que abre a lista.
const estrutura = w => {
  const filhos = [...w.find('.menu-container').element.children];
  return filhos
    .filter((el, i) => !(el.tagName === 'HR' && i === 0))
    .map(el => (el.tagName === 'HR' ? 'hr' : 'item'));
};

describe('separadores do menu da mensagem', () => {
  describe('na Equipe', () => {
    it('colega: só copiar, sem linha solta', () => {
      const w = montar({ equipe: true, copy: true, delete: false });
      expect(estrutura(w)).toEqual(['item']);
    });

    it('minha: copiar, um separador e apagar', () => {
      const w = montar({ equipe: true, copy: true, delete: true });
      expect(estrutura(w)).toEqual(['item', 'hr', 'item']);
    });

    it('com responder: um único separador antes de apagar', () => {
      const w = montar({
        equipe: true,
        replyTo: true,
        copy: true,
        delete: true,
      });
      expect(estrutura(w)).toEqual(['item', 'item', 'hr', 'item']);
    });

    it('anexo sem texto: só apagar, sem separador', () => {
      const w = montar({ equipe: true, delete: true });
      expect(estrutura(w)).toEqual(['item']);
    });
  });

  describe('fora da Equipe nada muda', () => {
    it('mantém o separador do meio, mesmo sem nada depois dele', () => {
      const w = montar({ copy: true });
      expect(estrutura(w)).toEqual(['item', 'hr']);
    });

    it('mantém os dois separadores', () => {
      const w = montar({ copy: true, copyLink: true, delete: true });
      expect(estrutura(w)).toEqual(['item', 'hr', 'item', 'hr', 'item']);
    });
  });
});
