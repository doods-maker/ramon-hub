import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { createPinia, setActivePinia } from 'pinia';
import RamonNav from '../RamonNav.vue';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const papel = ref('gestor');
const rotaAtual = ref('ramon_funil');

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
          template: '<a :data-rota="to.name"><slot /></a>',
        },
      },
    },
  });
};

const rotas = w =>
  w.findAll('a[data-rota]').map(a => a.attributes('data-rota'));

describe('RamonNav', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    papel.value = 'gestor';
    rotaAtual.value = 'ramon_funil';
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
    expect(w.findAll('a[data-rota]').length).toBe(4);
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
});
