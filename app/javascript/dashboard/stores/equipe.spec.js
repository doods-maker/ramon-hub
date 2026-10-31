import { setActivePinia, createPinia } from 'pinia';
import { useEquipeStore } from './equipe';
import EquipeAPI from 'dashboard/api/ramonEquipe';

vi.mock('dashboard/api/ramonEquipe', () => ({
  default: { get: vi.fn(), conversa: vi.fn() },
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

  it('carrega a caixa e as não-lidas da pessoa', () => {
    expect(useEquipeStore()).toMatchObject({ inboxId: 9, naoLidas: 3 });
  });

  it('avisa (som) mensagem de colega numa conversa da Equipe', () => {
    expect(useEquipeStore().avisar(notificacao())).toBe(true);
    expect(play).toHaveBeenCalled();
  });

  it('não avisa notificação de outra caixa nem de outro tipo', () => {
    const store = useEquipeStore();
    const outraCaixa = notificacao({ primary_actor: { id: 7, inbox_id: 1 } });
    const atribuicao = notificacao({
      notification_type: 'conversation_assignment',
    });

    expect(store.avisar(outraCaixa)).toBe(false);
    expect(store.avisar(atribuicao)).toBe(false);
    expect(play).not.toHaveBeenCalled();
  });

  it('não avisa quem está com a conversa aberta e à vista', () => {
    window.history.pushState({}, '', '/app/accounts/2/inbox/9/conversations/7');

    expect(useEquipeStore().avisar(notificacao())).toBe(false);
    expect(play).not.toHaveBeenCalled();
    window.history.pushState({}, '', '/');
  });
});
