import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import MessagesView from '../MessagesView.vue';

const rolar = async equipe => {
  const ordem = [];
  const elemento = document.createElement('div');
  elemento.id = 'message7';
  elemento.scrollIntoView = vi.fn(() => ordem.push('rolou'));
  document.body.appendChild(elemento);
  const ctx = {
    equipe,
    $nextTick: fn => fn(),
    makeMessagesRead: vi.fn(),
    scrollToBottom: vi.fn(),
    fetchPreviousMessages: vi.fn(async () => {
      ordem.push('carregando');
      await Promise.resolve();
      ordem.push('carregou');
    }),
  };
  MessagesView.methods.onScrollToMessage.call(ctx, { messageId: 7 });
  await vi.waitFor(() => expect(ordem).toHaveLength(3));
  return ordem;
};

describe('MessagesView · clicar na citação', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
  });
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('na Equipe rola só depois de carregar, senão a posição devolvida cancela a rolagem', async () => {
    expect(await rolar(true)).toEqual(['carregando', 'carregou', 'rolou']);
  });

  it('em conversa de cliente segue na ordem de antes', async () => {
    expect(await rolar(false)).toEqual(['rolou', 'carregando', 'carregou']);
  });
});
