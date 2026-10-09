import { mount } from '@vue/test-utils';
import FichaSistema from '../FichaSistema.vue';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));

const FICHA = {
  o_que_faz: 'Faz uma coisa.',
  quando: 'Todo dia às 08:00.',
  o_que_mexe: ['Mexe aqui.', 'E ali.'],
  travas: ['Trava 1.', 'Trava 2.', 'Trava 3.'],
  por_que: 'Porque sim.',
  mudar: {
    pedido: 'Peça ao Claude: "mude".',
    arquivos: ['app/x.rb', 'app/y.rb'],
    impacto: 'Muda tudo.',
  },
  fluxos: [],
};
const RouterLink = {
  name: 'RouterLink',
  props: ['to'],
  template: '<a :data-para="JSON.stringify(to)"><slot /></a>',
};
const montar = fluxo =>
  mount(FichaSistema, {
    props: { fluxo: { descricao: 'No código: X', ...fluxo } },
    global: { stubs: { RouterLink } },
  });

describe('FichaSistema', () => {
  it('regra fixa: as 6 seções, sem selo repetido (fica só o do cabeçalho) e sem botão de fluxo', () => {
    const w = montar({ fixa: true, ficha: FICHA });
    expect(w.find('[data-testid="ficha-selo"]').exists()).toBe(false);
    expect(w.get('[data-testid="ficha-o-que-faz"]').text()).toContain(
      'Faz uma coisa.'
    );
    expect(w.get('[data-testid="ficha-quando"]').text()).toContain('08:00');
    expect(w.findAll('[data-testid="ficha-o-que-mexe"] li')).toHaveLength(2);
    expect(w.findAll('[data-testid="ficha-travas"] li')).toHaveLength(3);
    expect(w.get('[data-testid="ficha-por-que"]').text()).toContain(
      'Why it stays in code'
    );
    expect(w.find('[data-testid="ficha-abrir-fluxo"]').exists()).toBe(false);
    expect(w.find('[data-testid="ficha-sem-fluxo"]').exists()).toBe(false);
    const mudar = w.get('[data-testid="ficha-mudar"]').text();
    ['Peça ao Claude', 'app/x.rb', 'app/y.rb', 'Muda tudo.'].forEach(t =>
      expect(mudar).toContain(t)
    );
    expect(w.get('[data-testid="sistema-descricao"]').text()).toContain(
      'No código: X'
    );
  });

  it('no fluxo: um botão por fluxo de verdade, com o modo; sem fluxo criado, avisa', () => {
    const fluxos = [
      { id: 7, nome: 'Reunião marcada', modo: 'normal', ativo: true },
      { id: 9, nome: 'Lembretes de reunião', modo: 'sombra', ativo: false },
    ];
    const w = montar({ fixa: false, ficha: { ...FICHA, fluxos } });
    expect(w.get('[data-testid="ficha-por-que"]').text()).toContain(
      'In a flow'
    );
    const botoes = w.findAll('[data-testid="ficha-abrir-fluxo"]');
    expect(botoes.map(b => JSON.parse(b.attributes('data-para')))).toEqual([
      { name: 'captain_automacoes_editor', params: { fluxoId: 7 } },
      { name: 'captain_automacoes_editor', params: { fluxoId: 9 } },
    ]);
    expect(botoes[0].text()).toContain('Reunião marcada');
    expect(botoes[0].text()).toContain('in command');
    expect(botoes[1].text()).toContain('off');

    const vazio = montar({ fixa: false, ficha: FICHA });
    expect(vazio.find('[data-testid="ficha-sem-fluxo"]').exists()).toBe(true);
  });

  it('sem ficha (desenho antigo): só os detalhes técnicos', () => {
    const w = montar({ fixa: false, ficha: null });
    expect(w.find('[data-testid="ficha-o-que-faz"]').exists()).toBe(false);
    expect(w.get('[data-testid="sistema-descricao"]').text()).toContain(
      'No código: X'
    );
  });
});
