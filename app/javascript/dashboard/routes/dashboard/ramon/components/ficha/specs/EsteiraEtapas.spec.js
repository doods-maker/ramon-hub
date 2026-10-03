import { mount } from '@vue/test-utils';
import EsteiraEtapas from '../EsteiraEtapas.vue';

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

  it('etapas passadas mostram check, futuras mostram posição', () => {
    const wrapper = mount(EsteiraEtapas, { props: { stages } });
    const selos = wrapper.findAll('[data-testid="esteira-selo"]');
    expect(selos[0].classes().join(' ')).toContain('bg-n-iris-9');
    expect(selos[2].text()).toBe('3');
  });

  it('lead em etapa perdida não marca a etapa de ganho anterior como concluída', () => {
    // is_won ANTES da etapa atual perdida — é o cenário real do bug (a esteira
    // reaproveita a etapa "Fechado" quando o lead é reaberto e perdido depois).
    const lostStages = [
      stages[0],
      { ...stages[2], id: 2, current: false },
      { ...stages[1], id: 3, current: true, is_lost: true },
    ];
    const wrapper = mount(EsteiraEtapas, { props: { stages: lostStages } });
    const selos = wrapper.findAll('[data-testid="esteira-selo"]');
    expect(selos[1].find('.i-lucide-check').exists()).toBe(false);
    expect(selos[1].text()).toBe('2');
  });

  it('etapa atual perdida usa selo em tom ruby', () => {
    const lostStages = [
      stages[0],
      { ...stages[2], id: 2, current: false },
      { ...stages[1], id: 3, current: true, is_lost: true },
    ];
    const wrapper = mount(EsteiraEtapas, { props: { stages: lostStages } });
    const selos = wrapper.findAll('[data-testid="esteira-selo"]');
    expect(selos[2].classes().join(' ')).toContain('bg-n-ruby-9');
  });
});
