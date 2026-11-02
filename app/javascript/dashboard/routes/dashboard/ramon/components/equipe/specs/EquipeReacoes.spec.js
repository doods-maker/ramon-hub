import { mount, flushPromises } from '@vue/test-utils';
import EquipeReacoes from '../EquipeReacoes.vue';
import EquipeAPI from 'dashboard/api/ramonEquipe';
import { useAlert } from 'dashboard/composables';
import { EMOJIS_REACAO } from 'dashboard/routes/dashboard/ramon/helpers/equipe';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/ramonEquipe', () => ({ default: { reagir: vi.fn() } }));

const REACOES = [
  { userId: 1, userName: 'Eu', emoji: '👍' },
  { userId: 2, userName: 'Ana antiga', emoji: '👍' },
  { userId: 3, userName: 'Bia', emoji: '🙏' },
];

const montar = (props = {}) =>
  mount(EquipeReacoes, {
    props: {
      conversationId: 43,
      messageId: 10,
      reacoes: REACOES,
      participantes: [{ id: 2, name: 'Ana' }],
      meuId: 1,
      podeReagir: true,
      ...props,
    },
  });

const selos = w => w.findAll('[data-testid="selo"]');
const barra = w => w.find('[data-testid="barra-reacoes"]');

describe('EquipeReacoes', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    EquipeAPI.reagir.mockResolvedValue({});
  });

  it('selo com total, nomes no título e estado minha', () => {
    const [joinha, reza] = selos(montar());
    expect(joinha.text()).toBe('👍 2');
    expect(joinha.attributes('title')).toBe('Eu, Ana');
    expect(joinha.classes()).toContain('border-n-blue-11');
    expect(reza.text()).toBe('🙏 1');
    expect(reza.attributes('title')).toBe('Bia');
    expect(reza.classes()).not.toContain('border-n-blue-11');
  });

  it('sem reação não há selo', () => {
    expect(selos(montar({ reacoes: [] }))).toHaveLength(0);
  });

  it('a barra traz os 6 emojis, na ordem, e o responder', () => {
    const botoes = barra(montar()).findAll('button');
    expect(botoes.slice(0, 6).map(b => b.text())).toEqual(EMOJIS_REACAO);
    expect(botoes[6].attributes('title')).toBe('RAMON.EQUIPE.RESPONDER');
  });

  it('responder avisa a mensagem, sem chamar a API', async () => {
    const w = montar();
    await barra(w).findAll('button')[6].trigger('click');
    expect(w.emitted('responder')).toHaveLength(1);
    expect(EquipeAPI.reagir).not.toHaveBeenCalled();
  });

  it('clicar na barra reage com o emoji', async () => {
    await barra(montar()).findAll('button')[1].trigger('click');
    expect(EquipeAPI.reagir).toHaveBeenCalledWith(43, 10, '❤️');
  });

  it('clicar no selo reage com o mesmo emoji', async () => {
    await selos(montar())[1].trigger('click');
    expect(EquipeAPI.reagir).toHaveBeenCalledWith(43, 10, '🙏');
  });

  it('falha na chamada avisa', async () => {
    EquipeAPI.reagir.mockRejectedValue(new Error('x'));
    await selos(montar())[0].trigger('click');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith('RAMON.EQUIPE.ERRO');
  });

  it('quem não participa vê os selos, sem barra e sem botões', async () => {
    const w = montar({ podeReagir: false, meuId: 99 });
    expect(selos(w)).toHaveLength(2);
    expect(barra(w).exists()).toBe(false);
    expect(w.findAll('button')).toHaveLength(0);
    await selos(w)[0].trigger('click');
    expect(EquipeAPI.reagir).not.toHaveBeenCalled();
  });
});
