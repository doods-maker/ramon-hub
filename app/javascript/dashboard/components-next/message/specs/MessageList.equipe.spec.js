import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import MessageList from '../MessageList.vue';

const selecionada = ref({ id: 43, inbox_id: 7 });

vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: key =>
    ({
      'inboxes/getInbox': ref(id => ({ id, equipe: id === 7 })),
      getSelectedChat: selecionada,
    })[key] ?? ref(null),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/api/inbox/message.js', () => ({ default: {} }));
vi.mock('../Message.vue', () => ({
  default: {
    name: 'MensagemFalsa',
    props: ['primeiroDoAutor', 'groupWithNext', 'inboxId'],
    render: () => null,
  },
}));

// 02/11/2026, meio-dia em São Paulo.
const AGORA = Date.UTC(2026, 10, 2, 15, 0, 0);
const SEG = AGORA / 1000;
const DIA = 86400;

const msg = (id, autor, createdAt, extra = {}) => ({
  id,
  created_at: createdAt,
  sender_id: autor,
  message_type: 1,
  status: 'sent',
  ...extra,
});

const montar = messages =>
  mount(MessageList, { props: { currentUserId: 1, messages } });

const mensagens = w => w.findAllComponents({ name: 'MensagemFalsa' });
const dias = w =>
  w.findAll('[data-testid="equipe-dia"]').map(item => item.text());

describe('MessageList na caixa Equipe', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: AGORA });
    selecionada.value = { id: 43, inbox_id: 7 };
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('margem lateral de 8% só na Equipe', () => {
    const classes = () =>
      montar([msg(1, 2, SEG)])
        .find('ul')
        .classes();
    expect(classes()).toContain('md:px-[8%]');
    selecionada.value = { id: 44, inbox_id: 8 };
    expect(classes()).not.toContain('md:px-[8%]');
    expect(classes()).toContain('px-4');
  });

  it('marca a primeira do bloco e agrupa o autor em minutos diferentes', () => {
    const w = montar([
      msg(1, 2, SEG - 600),
      msg(2, 2, SEG - 300),
      msg(3, 3, SEG - 200),
    ]);
    const lista = mensagens(w);
    expect(lista.map(m => m.props('primeiroDoAutor'))).toEqual([
      true,
      false,
      true,
    ]);
    expect(lista.map(m => m.props('groupWithNext'))).toEqual([
      true,
      false,
      false,
    ]);
  });

  it('virar o dia abre bloco novo', () => {
    const w = montar([msg(1, 2, SEG - DIA), msg(2, 2, SEG)]);
    const lista = mensagens(w);
    expect(lista[0].props('groupWithNext')).toBe(false);
    expect(lista[1].props('primeiroDoAutor')).toBe(true);
  });

  it('atividade no meio abre bloco novo', () => {
    const w = montar([
      msg(1, 2, SEG - 300),
      msg(2, 2, SEG - 200, { message_type: 2 }),
      msg(3, 2, SEG - 100),
    ]);
    expect(mensagens(w)[2].props('primeiroDoAutor')).toBe(true);
  });

  it('não agrupa com a próxima que falhou', () => {
    const w = montar([
      msg(1, 2, SEG - 60),
      msg(2, 2, SEG, { status: 'failed' }),
    ]);
    expect(mensagens(w)[0].props('groupWithNext')).toBe(false);
  });

  it('põe um separador por dia, com Hoje, Ontem e data', () => {
    const w = montar([
      msg(1, 2, SEG - 3 * DIA),
      msg(2, 2, SEG - DIA),
      msg(3, 2, SEG - DIA + 60),
      msg(4, 2, SEG),
    ]);
    expect(dias(w)).toEqual([
      '30/10/2026',
      'RAMON.EQUIPE.ONTEM',
      'RAMON.EQUIPE.HOJE',
    ]);
  });

  it('mensagem em envio (sem caixa) recebe a caixa da conversa', () => {
    const w = montar([msg(9, undefined, SEG)]);
    expect(mensagens(w)[0].props('inboxId')).toBe(7);
  });

  describe('fora da Equipe', () => {
    beforeEach(() => {
      selecionada.value = { id: 44, inbox_id: 8 };
    });

    it('sem separador de dia e sem primeiroDoAutor', () => {
      const w = montar([msg(1, 2, SEG - DIA), msg(2, 2, SEG)]);
      expect(dias(w)).toEqual([]);
      expect(mensagens(w).map(m => m.props('primeiroDoAutor'))).toEqual([
        false,
        false,
      ]);
    });

    it('agrupa só no mesmo minuto, como sempre', () => {
      const w = montar([
        msg(1, 2, SEG),
        msg(2, 2, SEG + 30),
        msg(3, 2, SEG + 300),
      ]);
      expect(mensagens(w).map(m => m.props('groupWithNext'))).toEqual([
        true,
        false,
        false,
      ]);
    });
  });
});
