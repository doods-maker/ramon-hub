import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { useDashboardBootstrap } from '../useDashboardBootstrap';

const dispatch = vi.fn();
const naoLidasLigado = ref(true);

vi.mock('vuex', () => ({ useStore: () => ({ dispatch }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: nome =>
    nome === 'getCurrentAccountId' ? ref(1) : ref(() => naoLidasLigado.value),
}));

const montar = () =>
  mount({
    setup() {
      useDashboardBootstrap();
      return {};
    },
    template: '<div />',
  });

describe('useDashboardBootstrap', () => {
  beforeEach(() => {
    dispatch.mockClear();
    naoLidasLigado.value = true;
  });

  it('carrega o que o sidebar do Chatwoot carregava, sem depender do menu', () => {
    montar();
    const acoes = dispatch.mock.calls.map(([acao, arg]) =>
      arg ? `${acao}:${arg}` : acao
    );
    expect(acoes).toEqual(
      expect.arrayContaining([
        'labels/get',
        'inboxes/get',
        'notifications/unReadCount',
        'teams/get',
        'attributes/get',
        'customViews/get:conversation',
        'customViews/get:contact',
        'conversationUnreadCounts/get',
      ])
    );
  });

  it('feature de não lidas desligada limpa o contador', () => {
    naoLidasLigado.value = false;
    montar();
    expect(dispatch).toHaveBeenCalledWith('conversationUnreadCounts/clear');
  });
});
