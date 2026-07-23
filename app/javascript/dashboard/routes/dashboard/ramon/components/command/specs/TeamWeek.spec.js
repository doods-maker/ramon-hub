import { mount } from '@vue/test-utils';
import TeamWeek from '../TeamWeek.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const team = [
  {
    user_id: 1,
    name: 'Eduardo Schlata',
    avatar_url: null,
    won_count: 3,
    won_value: 95000,
    activities_count: 28,
  },
  {
    user_id: 2,
    name: 'Ramon',
    avatar_url: null,
    won_count: 0,
    won_value: 0,
    activities_count: 9,
  },
];

const mountTeam = props =>
  mount(TeamWeek, { props, global: { mocks: { $t: k => k } } });

describe('TeamWeek.vue', () => {
  it('renders initials, wins in teal and a dash for who has none', () => {
    const wrapper = mountTeam({ team, nps: null });
    const rows = wrapper.findAll('[data-testid="team-row"]');
    expect(rows[0].text()).toContain('ES');
    expect(rows[0].text()).toContain('RAMON.COMMAND.TEAM.WON');
    expect(rows[1].text()).toContain('—');
    expect(rows[1].text()).toContain('RAMON.COMMAND.TEAM.ACTIONS');
  });

  it('shows the NPS footer only when there are responses', () => {
    const withNps = mountTeam({ team, nps: { media: 9.4, respostas: 3 } });
    expect(withNps.find('[data-testid="team-nps"]').exists()).toBe(true);
    const withoutNps = mountTeam({ team, nps: { media: null, respostas: 0 } });
    expect(withoutNps.find('[data-testid="team-nps"]').exists()).toBe(false);
  });
});
