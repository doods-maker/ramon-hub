import { mount } from '@vue/test-utils';
import EsteiraEtapas from '../EsteiraEtapas.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const stages = [
  {
    id: 1,
    name: 'Novo',
    color: '#888',
    current: false,
    entered_at: '2026-08-08T12:00:00Z',
    is_won: false,
    is_lost: false,
  },
  {
    id: 2,
    name: 'Reunião',
    color: '#8a5c33',
    current: true,
    entered_at: '2026-08-11T12:00:00Z',
    is_won: false,
    is_lost: false,
  },
  {
    id: 3,
    name: 'Fechado',
    color: '#2e7d5b',
    current: false,
    entered_at: null,
    is_won: true,
    is_lost: false,
  },
];

describe('EsteiraEtapas', () => {
  it('renderiza um selo por etapa e marca a atual', () => {
    const wrapper = mount(EsteiraEtapas, { props: { stages } });
    expect(wrapper.findAll('[data-testid="esteira-etapa"]')).toHaveLength(3);
    expect(wrapper.find('[data-testid="esteira-atual"]').text()).toContain(
      'Reunião'
    );
  });

  it('barra feita/atual na cor da etapa, futura cinza', () => {
    const wrapper = mount(EsteiraEtapas, { props: { stages } });
    const barras = wrapper.findAll('[data-testid="esteira-selo"]');
    expect(barras[0].classes()).toContain('bg-[var(--stage)]');
    expect(barras[1].classes()).toContain('bg-[var(--stage)]');
    expect(barras[2].classes()).toContain('bg-n-slate-4');
    expect(
      wrapper.findAll('[data-testid="esteira-etapa"]')[0].attributes('style')
    ).toContain('#888');
  });

  it('lead em etapa perdida não marca a etapa de ganho anterior como feita', () => {
    // is_won ANTES da etapa atual perdida — é o cenário real do bug (a esteira
    // reaproveita a etapa "Fechado" quando o lead é reaberto e perdido depois).
    const lostStages = [
      stages[0],
      { ...stages[2], id: 2, current: false },
      { ...stages[1], id: 3, current: true, is_lost: true },
    ];
    const wrapper = mount(EsteiraEtapas, { props: { stages: lostStages } });
    const barras = wrapper.findAll('[data-testid="esteira-selo"]');
    expect(barras[1].classes()).toContain('bg-n-slate-4');
  });

  it('etapa atual perdida usa barra e nome em tom ruby', () => {
    const lostStages = [
      stages[0],
      { ...stages[2], id: 2, current: false },
      { ...stages[1], id: 3, current: true, is_lost: true },
    ];
    const wrapper = mount(EsteiraEtapas, { props: { stages: lostStages } });
    const barras = wrapper.findAll('[data-testid="esteira-selo"]');
    expect(barras[2].classes()).toContain('bg-n-ruby-9');
    expect(wrapper.find('[data-testid="esteira-atual"]').classes()).toContain(
      'text-n-ruby-11'
    );
  });
});
