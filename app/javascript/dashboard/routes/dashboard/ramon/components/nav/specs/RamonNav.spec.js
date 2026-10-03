import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { createPinia, setActivePinia } from 'pinia';
import RamonNav from '../RamonNav.vue';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const papel = ref('gestor');
const rotaAtual = ref('ramon_funil');
const naoLidasNotificacoes = ref(5);
const caixas = ref([
  { id: 1, name: 'Comercial' },
  { id: 2, name: 'Escritório' },
]);

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: nome =>
    ({
      'notifications/getUnreadCount': naoLidasNotificacoes,
      'inboxes/getInboxes': caixas,
    })[nome],
}));

vi.mock('../../../composables/useRamonPapel', () => ({
  useRamonPapel: () => ({ papel }),
}));
vi.mock('../../../composables/useNavContadores', () => ({
  useNavContadores: () => ({
    conversas: ref(3),
    agenda: ref(0),
    conteudo: ref(2),
    carregar: vi.fn(),
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({
    get name() {
      return rotaAtual.value;
    },
  }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: ref({}) }),
}));
vi.mock('dashboard/components-next/sidebar/SidebarProfileMenu.vue', () => ({
  default: { props: ['subtitle'], template: '<div>{{ subtitle }}</div>' },
}));
vi.mock(
  'dashboard/components-next/NewConversation/ComposeConversation.vue',
  () => ({ default: { template: '<div><slot name="trigger" /></div>' } })
);

const montar = ({ podeAvisar = true } = {}) => {
  useChegadasStore().podeAvisar = podeAvisar;
  return mount(RamonNav, {
    global: {
      stubs: {
        RouterLink: {
          props: ['to'],
          template:
            '<a :data-rota="to.name" :data-caixa="to.params && to.params.inbox_id"><slot /></a>',
        },
      },
    },
  });
};

// Itens do menu (o sino do topo fica de fora).
const rotas = w =>
  w
    .findAll('a[data-rota]')
    .map(a => a.attributes('data-rota'))
    .filter(r => r !== 'inbox_view');

describe('RamonNav', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    papel.value = 'gestor';
    rotaAtual.value = 'ramon_funil';
    naoLidasNotificacoes.value = 5;
    caixas.value = [
      { id: 1, name: 'Comercial' },
      { id: 2, name: 'Escritório' },
    ];
  });

  it('gestor: 8 links + Mais, Funil aceso', () => {
    const w = montar();
    expect(rotas(w)).toEqual([
      'ramon_index',
      'home',
      'ramon_funil',
      'ramon_pessoas',
      'ramon_agenda',
      'ramon_calculos',
      'ramon_conteudo',
      'ramon_relatorios',
    ]);
    expect(w.find('a[data-rota="ramon_funil"]').classes()).toContain(
      'text-n-blue-11'
    );
    expect(w.find('a[data-rota="home"]').classes()).not.toContain(
      'text-n-blue-11'
    );
    expect(w.text()).toContain('RAMON.MENU.MAIS');
    expect(w.text()).toContain('RAMON.MENU.PAPEL.gestor');
  });

  it('contadores: conversas e conteúdo aparecem, agenda zerada some', () => {
    const w = montar();
    expect(w.find('a[data-rota="home"]').text()).toContain('3');
    expect(w.find('a[data-rota="ramon_conteudo"]').text()).toContain('2');
    expect(w.find('a[data-rota="ramon_agenda"]').text()).not.toMatch(/\d/);
  });

  it('recepção: 4 itens e botão Chegou cliente que pede o painel', async () => {
    papel.value = 'recepcao';
    const w = montar();
    expect(rotas(w).length).toBe(4);
    await w.find('[data-test="chegou-cliente"]').trigger('click');
    expect(useChegadasStore().painelPedido).toBe(1);
  });

  it('não-recepção não vê Chegou cliente', () => {
    expect(montar().find('[data-test="chegou-cliente"]').exists()).toBe(false);
  });

  it('recepção sem permissão no backend não vê botão morto', () => {
    papel.value = 'recepcao';
    const w = montar({ podeAvisar: false });
    expect(w.find('[data-test="chegou-cliente"]').exists()).toBe(false);
  });

  it('Buscar abre a command bar', async () => {
    const ouvinte = vi.fn();
    emitter.on(BUS_EVENTS.OPEN_COMMAND_BAR, ouvinte);
    await montar().find('[data-test="buscar"]').trigger('click');
    expect(ouvinte).toHaveBeenCalled();
    emitter.off(BUS_EVENTS.OPEN_COMMAND_BAR, ouvinte);
  });

  it('Mais abre ao clicar e abre sozinho numa rota dele', async () => {
    const w = montar();
    expect(w.find('a[data-rota="ramon_tv"]').exists()).toBe(false);
    await w.find('[data-test="mais"]').trigger('click');
    expect(w.find('a[data-rota="ramon_tv"]').exists()).toBe(true);

    rotaAtual.value = 'ramon_tv';
    const aberto = montar();
    expect(aberto.find('a[data-rota="ramon_tv"]').classes()).toContain(
      'text-n-blue-11'
    );
  });

  it('sino leva às notificações, com contador só se > 0, e acende lá', () => {
    let w = montar();
    expect(w.find('a[data-rota="inbox_view"]').text()).toContain('5');
    naoLidasNotificacoes.value = 0;
    w = montar();
    expect(w.find('a[data-rota="inbox_view"]').text()).not.toMatch(/\d/);

    rotaAtual.value = 'inbox_view';
    w = montar();
    expect(w.find('a[data-rota="inbox_view"]').classes()).toContain(
      'text-n-blue-11'
    );
    expect(w.find('a[data-rota="home"]').classes()).not.toContain(
      'text-n-blue-11'
    );
  });

  it('Conversas acesa mostra menções, participando, não atendidas e as caixas', () => {
    expect(montar().find('a[data-rota="conversation_mentions"]').exists()).toBe(
      false
    );

    rotaAtual.value = 'home';
    const w = montar();
    expect(rotas(w)).toEqual(
      expect.arrayContaining([
        'conversation_mentions',
        'conversation_participating',
        'conversation_unattended',
      ])
    );
    expect(
      w.findAll('a[data-rota="inbox_dashboard"]').map(a => a.text())
    ).toEqual(['Comercial', 'Escritório']);
    expect(w.find('a[data-caixa="2"]').exists()).toBe(true);
  });

  it('uma caixa só: não lista caixas', () => {
    caixas.value = [{ id: 1, name: 'Comercial' }];
    rotaAtual.value = 'home';
    expect(montar().find('a[data-rota="inbox_dashboard"]').exists()).toBe(
      false
    );
  });

  it('gestor que pode avisar tem "Avisar chegada" no Mais', async () => {
    const w = montar();
    await w.find('[data-test="mais"]').trigger('click');
    await w.find('[data-test="mais-avisar-chegada"]').trigger('click');
    expect(useChegadasStore().painelPedido).toBe(1);

    const semPermissao = montar({ podeAvisar: false });
    await semPermissao.find('[data-test="mais"]').trigger('click');
    expect(
      semPermissao.find('[data-test="mais-avisar-chegada"]').exists()
    ).toBe(false);
  });
});
