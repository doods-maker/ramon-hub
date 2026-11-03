import { setActivePinia, createPinia } from 'pinia';
import { useEquipeStore } from './equipe';
import EquipeAPI from 'dashboard/api/ramonEquipe';

vi.mock('dashboard/api/ramonEquipe', () => ({
  default: { get: vi.fn(), conversa: vi.fn(), participantes: vi.fn() },
}));

const notificacao = (over = {}) => ({
  notification_type: 'participating_conversation_new_message',
  primary_actor: { id: 7, inbox_id: 9, meta: { sender: { name: 'Geral' } } },
  secondary_actor: { content: 'bom dia', sender: { name: 'Ana' } },
  ...over,
});

describe('useEquipeStore', () => {
  let play;

  beforeEach(async () => {
    setActivePinia(createPinia());
    play = vi.fn(() => Promise.resolve());
    vi.stubGlobal(
      'Audio',
      vi.fn(() => ({ play }))
    );
    EquipeAPI.get.mockResolvedValue({ data: { inbox_id: 9, nao_lidas: 3 } });
    await useEquipeStore().carregar();
  });

  afterEach(() => vi.unstubAllGlobals());

  it('na Intranet (caixa ainda não carregada) carrega e avisa', async () => {
    setActivePinia(createPinia());

    expect(await useEquipeStore().avisar(notificacao())).toBe(true);
    expect(useEquipeStore().inboxId).toBe(9);
  });

  it('carrega a caixa e as não-lidas da pessoa', () => {
    expect(useEquipeStore()).toMatchObject({ inboxId: 9, naoLidas: 3 });
  });

  it('carrega participantes em camelCase e atualiza só a pessoa certa', async () => {
    EquipeAPI.participantes.mockResolvedValue({
      data: [
        { id: 1, name: 'Eu', thumbnail: 'a', last_seen_at: 10 },
        { id: 2, name: 'Ana', thumbnail: 'b', last_seen_at: null },
      ],
    });
    const store = useEquipeStore();
    await store.carregarParticipantes(7);
    expect(store.participantes[7][1]).toEqual({
      id: 2,
      name: 'Ana',
      thumbnail: 'b',
      lastSeenAt: null,
    });

    store.atualizarLeitura({ conversationId: 7, userId: 2, lastSeenAt: 99 });
    store.atualizarLeitura({ conversationId: 8, userId: 2, lastSeenAt: 5 });
    expect(store.participantes[7].map(p => p.lastSeenAt)).toEqual([10, 99]);
    expect(store.participantes[8]).toBeUndefined();
  });

  it('atualizarLeitura: evento fora de ordem não volta a leitura para trás', () => {
    const store = useEquipeStore();
    store.participantes[7] = [{ id: 2, lastSeenAt: null }];

    store.atualizarLeitura({ conversationId: 7, userId: 2, lastSeenAt: 100 });
    expect(store.participantes[7][0].lastSeenAt).toBe(100);

    store.atualizarLeitura({ conversationId: 7, userId: 2, lastSeenAt: 50 });
    expect(store.participantes[7][0].lastSeenAt).toBe(100);
  });

  it('avisa (som) mensagem de colega numa conversa da Equipe', async () => {
    expect(await useEquipeStore().avisar(notificacao())).toBe(true);
    expect(play).toHaveBeenCalled();
  });

  describe('notificação do sistema', () => {
    let Notificacao;
    const marcacao = '[@Eduardo](mention://user/1/Eduardo) bom dia';
    const chat1a1 = {
      id: 7,
      inbox_id: 9,
      equipe_tipo: '1a1',
      meta: { sender: { name: 'Ana e Bia' } },
    };

    beforeEach(() => {
      Notificacao = vi.fn();
      Notificacao.permission = 'granted';
      vi.stubGlobal('Notification', Notificacao);
    });

    it('marcação: "Ana te marcou · Geral", corpo sem mention://', async () => {
      await useEquipeStore().avisar(
        notificacao({
          notification_type: 'conversation_mention',
          secondary_actor: { content: marcacao, sender: { name: 'Ana' } },
        })
      );
      expect(Notificacao).toHaveBeenCalledWith('Ana te marcou · Geral', {
        body: '@Eduardo bom dia',
        tag: 'equipe-7',
      });
    });

    it('aviso comum: "Ana · Geral", corpo sem mention://', async () => {
      await useEquipeStore().avisar(
        notificacao({
          secondary_actor: { content: marcacao, sender: { name: 'Ana' } },
        })
      );
      expect(Notificacao).toHaveBeenCalledWith('Ana · Geral', {
        body: '@Eduardo bom dia',
        tag: 'equipe-7',
      });
    });

    it('1:1: só "Ana te marcou", sem o nome do contato sintético', async () => {
      await useEquipeStore().avisar(
        notificacao({
          notification_type: 'conversation_mention',
          primary_actor: chat1a1,
        })
      );
      expect(Notificacao.mock.calls[0][0]).toBe('Ana te marcou');
    });

    it('1:1: aviso comum mostra só o nome da pessoa', async () => {
      await useEquipeStore().avisar(notificacao({ primary_actor: chat1a1 }));
      expect(Notificacao.mock.calls[0][0]).toBe('Ana');
    });
  });

  it('não avisa notificação de outra caixa nem de outro tipo', async () => {
    const store = useEquipeStore();
    const outraCaixa = notificacao({ primary_actor: { id: 7, inbox_id: 1 } });
    const atribuicao = notificacao({
      notification_type: 'conversation_assignment',
    });

    expect(await store.avisar(outraCaixa)).toBe(false);
    expect(await store.avisar(atribuicao)).toBe(false);
    expect(play).not.toHaveBeenCalled();
  });

  it('não avisa quem está com a conversa aberta e à vista', async () => {
    window.history.pushState({}, '', '/app/accounts/2/inbox/9/conversations/7');

    expect(await useEquipeStore().avisar(notificacao())).toBe(false);
    expect(play).not.toHaveBeenCalled();
    window.history.pushState({}, '', '/');
  });
});
