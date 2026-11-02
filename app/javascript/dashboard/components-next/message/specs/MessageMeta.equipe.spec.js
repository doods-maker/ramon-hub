import { defineComponent, h, nextTick, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createI18n } from 'vue-i18n';
import MessageMeta from '../MessageMeta.vue';
import { provideMessageContext } from '../provider';
import { MESSAGE_TYPES, ORIENTATION } from '../constants';
import { useEquipeStore } from 'dashboard/stores/equipe';
import ramon from 'dashboard/i18n/locale/pt_BR/ramon.json';

const canalApi = ref(false);

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref([]),
}));
vi.mock('dashboard/composables/useInbox', () => ({
  useInbox: () =>
    new Proxy(
      {},
      { get: (_, chave) => (chave === 'isAPIInbox' ? canalApi : ref(false)) }
    ),
}));

const EU = 1;
const CRIADA = 100;
const CONVERSA = 43;

const pessoa = (id, name, lastSeenAt) => ({ id, name, lastSeenAt });
const eu = pessoa(EU, 'Eu', 0);

const montar = (contexto = {}) => {
  const Provedor = defineComponent({
    setup() {
      provideMessageContext({
        status: ref('sent'),
        isPrivate: ref(false),
        createdAt: ref(CRIADA),
        sourceId: ref(null),
        messageType: ref(MESSAGE_TYPES.OUTGOING),
        contentAttributes: ref({}),
        isEquipe: ref(true),
        orientation: ref(ORIENTATION.RIGHT),
        conversationId: ref(CONVERSA),
        currentUserId: ref(EU),
        equipeTipo: ref('grupo'),
        participaEquipe: ref(true),
        ...contexto,
      });
      return () => h(MessageMeta);
    },
  });
  return mount(Provedor, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: ramon },
          missingWarn: false,
          fallbackWarn: false,
        }),
      ],
      directives: {
        tooltip: (el, { value }) => el.setAttribute('data-titulo', value || ''),
      },
    },
  });
};

const com = lista => {
  useEquipeStore().participantes[CONVERSA] = lista;
};
const titulo = w => w.find('[data-titulo]').attributes('data-titulo');
const iconeDuplo = w => w.find('.i-lucide-check-check');
const iconeSimples = w => w.find('.i-lucide-check');

describe('MessageMeta: vistos na Equipe', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    canalApi.value = false;
  });

  it('todos leram: ✓✓ azul, "Visto por todos"', () => {
    com([eu, pessoa(2, 'Ana', 100), pessoa(3, 'Bia', 150)]);
    const w = montar();
    expect(iconeDuplo(w).classes()).toContain('text-n-blue-11');
    expect(titulo(w)).toBe('Visto por todos');
  });

  it('faltando alguém: ✓✓ cinza e quem falta', () => {
    com([eu, pessoa(2, 'Ana', 100), pessoa(3, 'Bia', 50)]);
    const w = montar();
    expect(iconeDuplo(w).classes()).not.toContain('text-n-blue-11');
    expect(iconeDuplo(w).classes()).toContain('text-n-slate-11');
    expect(titulo(w)).toBe('Visto por 1 de 2. Falta: Bia.');
  });

  it('título exato com vários faltando', () => {
    com([
      eu,
      ...['Ana', 'Bia', 'Cris', 'Duda', 'Edu'].map((nome, i) =>
        pessoa(i + 2, nome, 200)
      ),
      pessoa(7, 'Tamires', null),
      pessoa(8, 'Thaís', 50),
    ]);
    expect(titulo(montar())).toBe('Visto por 5 de 7. Falta: Tamires, Thaís.');
  });

  it('quem saiu do chat não entra na conta', () => {
    // A Bia saiu: não vem na lista, e o que falta dela não segura o azul.
    com([eu, pessoa(2, 'Ana', 100)]);
    expect(iconeDuplo(montar()).classes()).toContain('text-n-blue-11');
  });

  it('o evento de leitura vira azul na hora', async () => {
    com([eu, pessoa(2, 'Ana', 50)]);
    const w = montar();
    expect(iconeDuplo(w).classes()).not.toContain('text-n-blue-11');
    useEquipeStore().atualizarLeitura({
      conversationId: CONVERSA,
      userId: 2,
      lastSeenAt: 100,
    });
    await nextTick();
    expect(iconeDuplo(w).classes()).toContain('text-n-blue-11');
  });

  describe('1:1', () => {
    const umAum = { equipeTipo: ref('1a1') };

    it('o outro leu: azul e "Visto"', () => {
      com([eu, pessoa(2, 'Ana', 100)]);
      const w = montar(umAum);
      expect(iconeDuplo(w).classes()).toContain('text-n-blue-11');
      expect(titulo(w)).toBe('Visto');
    });

    it('o outro não leu: cinza, sem "Falta"', () => {
      com([eu, pessoa(2, 'Ana', 50)]);
      const w = montar(umAum);
      expect(iconeDuplo(w).classes()).not.toContain('text-n-blue-11');
      expect(titulo(w)).toBe('');
    });
  });

  it('lista não carregada: um ✓ cinza, sem título, nunca azul', () => {
    const w = montar({ participaEquipe: ref(null) });
    expect(iconeSimples(w).exists()).toBe(true);
    expect(iconeDuplo(w).exists()).toBe(false);
    expect(iconeSimples(w).classes()).not.toContain('text-n-blue-11');
    expect(titulo(w)).toBe('');
  });

  it('sozinho no chat: um ✓, sem "Visto por 0 de 0"', () => {
    com([eu]);
    const w = montar();
    expect(iconeSimples(w).exists()).toBe(true);
    expect(titulo(w)).toBe('');
  });

  it('mensagem de colega: sem ✓', () => {
    com([eu, pessoa(2, 'Ana', 100)]);
    const w = montar({ orientation: ref(ORIENTATION.LEFT) });
    expect(iconeDuplo(w).exists()).toBe(false);
    expect(iconeSimples(w).exists()).toBe(false);
  });

  it('admin de fora: sem ✓, nem na mensagem antiga dele', () => {
    com([pessoa(2, 'Ana', 100), pessoa(3, 'Bia', 100)]);
    const w = montar({ participaEquipe: ref(false) });
    expect(iconeDuplo(w).exists()).toBe(false);
    expect(iconeSimples(w).exists()).toBe(false);
  });

  it('pendência segue o relógio, sem título de visto', () => {
    com([eu, pessoa(2, 'Ana', 100)]);
    const w = montar({ status: ref('progress') });
    expect(iconeDuplo(w).exists()).toBe(false);
    expect(w.find('[class*="i-lucide-clock"]').exists()).toBe(true);
  });

  it('falha segue sem indicador', () => {
    com([eu, pessoa(2, 'Ana', 100)]);
    const w = montar({ status: ref('failed') });
    expect(iconeDuplo(w).exists()).toBe(false);
    expect(iconeSimples(w).exists()).toBe(false);
  });

  it('fora da Equipe nada muda: status do canal e azul nativo', () => {
    canalApi.value = true;
    com([eu, pessoa(2, 'Ana', 0)]);
    const w = montar({
      isEquipe: ref(false),
      status: ref('read'),
      participaEquipe: ref(null),
    });
    expect(iconeDuplo(w).classes()).toContain('text-[#7EB6FF]');
    expect(titulo(w)).not.toContain('Visto');
  });
});
