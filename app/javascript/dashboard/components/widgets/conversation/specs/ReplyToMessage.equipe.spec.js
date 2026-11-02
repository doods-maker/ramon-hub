import { mount } from '@vue/test-utils';
import ReplyToMessage from '../ReplyToMessage.vue';

vi.mock('vue-i18n', async original => ({
  ...(await original()),
  useI18n: () => ({ t: key => key }),
}));

const montar = props =>
  mount(ReplyToMessage, {
    props,
    global: {
      stubs: { Button: true, FluentIcon: true },
      mocks: { $t: key => key },
      directives: { tooltip: {} },
    },
  });

const mensagem = {
  id: 9,
  content: '[@Eduardo](mention://user/1/Eduardo) o cliente chegou?',
  sender: { id: 2, name: 'Brenda' },
  attachments: [],
};

describe('ReplyToMessage', () => {
  it('Equipe: autor e texto limpo, sem "Respondendo a"', () => {
    const w = montar({ message: mensagem, equipe: true, meuId: 1 });
    expect(w.text()).toContain('Brenda');
    expect(w.text()).toContain('@Eduardo o cliente chegou?');
    expect(w.text()).not.toContain('mention://');
    expect(w.text()).not.toContain('REPLYING_TO');
  });

  it('Equipe: "Você" quando a mensagem citada é minha', () => {
    const w = montar({
      message: { ...mensagem, sender: { id: 1, name: 'Eduardo' } },
      equipe: true,
      meuId: 1,
    });
    expect(w.text()).toContain('RAMON.EQUIPE.VOCE');
    expect(w.text()).not.toContain('Brenda');
  });

  it('Equipe: dispensar a citação continua emitindo', async () => {
    const w = montar({ message: mensagem, equipe: true, meuId: 1 });
    await w.findComponent({ name: 'Button' }).vm.$emit('click', {
      stopPropagation: () => {},
    });
    expect(w.emitted('dismiss')).toBeTruthy();
  });

  it('o X é maior na Equipe', () => {
    const tamanho = props =>
      montar({ message: mensagem, ...props })
        .findComponent({ name: 'Button' })
        .props('size');
    expect(tamanho({ equipe: true, meuId: 1 })).toBe('sm');
    expect(tamanho({})).toBe('xs');
  });

  it('fora da Equipe fica como o nativo: "Respondendo a", sem autor', () => {
    const w = montar({ message: mensagem });
    expect(w.text()).toContain('CONVERSATION.REPLYBOX.REPLYING_TO');
    expect(w.text()).not.toContain('Brenda');
    expect(w.find('.reply-editor').exists()).toBe(true);
  });
});
