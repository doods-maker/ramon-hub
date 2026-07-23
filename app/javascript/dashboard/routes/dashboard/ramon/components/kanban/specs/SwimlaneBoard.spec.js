import { mount } from '@vue/test-utils';
import SwimlaneBoard from '../SwimlaneBoard.vue';
import SwimlaneCell from '../SwimlaneCell.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const stubStore = {
  getters: {
    'leadConfig/getChannels': [{ key: 'whatsapp', label: 'WhatsApp' }],
    'leadConfig/getStages': [],
  },
  dispatch: vi.fn(),
};

const stages = [
  { id: 1, name: 'Novo', color: '#a00' },
  { id: 2, name: 'Triagem', color: '#0a0' },
];

const leads = [
  {
    id: 10,
    name: 'Ana',
    lead_stage_id: 1,
    position: 0,
    thesis_id: 5,
    thesis_name: 'B31',
    sdr_id: 3,
    sdr_name: 'Edu',
    channel: 'whatsapp',
    value: 100,
  },
  {
    id: 11,
    name: 'Bia',
    lead_stage_id: 2,
    position: 0,
    thesis_id: 5,
    thesis_name: 'B31',
    sdr_id: 4,
    sdr_name: 'Ramon',
    channel: 'whatsapp',
    value: 50,
  },
  {
    id: 12,
    name: 'Caio',
    lead_stage_id: 1,
    position: 1,
    thesis_id: null,
    thesis_name: null,
    sdr_id: 3,
    sdr_name: 'Edu',
    channel: 'whatsapp',
    value: 0,
  },
];

const mountBoard = (props = {}) =>
  mount(SwimlaneBoard, {
    props: { stages, leads, groupBy: 'thesis', ...props },
    global: {
      mocks: { $t: k => k },
      plugins: [
        {
          install: app => {
            app.config.globalProperties.$store = stubStore;
          },
        },
      ],
    },
  });

describe('SwimlaneBoard', () => {
  it('agrupa por tese com "Sem grupo" por último', () => {
    const wrapper = mountBoard();
    const names = wrapper
      .findAll('[data-testid="swimlane-name"]')
      .map(n => n.text());
    expect(names).toEqual(['B31', 'RAMON.KANBAN.LANES.NO_GROUP']);
  });

  it('mostra contagem e soma na célula-resumo da raia', () => {
    const wrapper = mountBoard();
    const summary = wrapper.find('[data-testid="swimlane-summary"]');
    expect(summary.text()).toContain('2');
    expect(summary.text()).toContain('150');
  });

  it('distribui os cards da raia pelas etapas', () => {
    const wrapper = mountBoard();
    const firstLane = wrapper.findAll('[data-testid="swimlane"]')[0];
    const cells = firstLane.findAllComponents(SwimlaneCell);
    expect(cells).toHaveLength(2);
    expect(cells[0].text()).toContain('Ana');
    expect(cells[1].text()).toContain('Bia');
  });

  it('agrupar por dono (sdr) refaz as raias', async () => {
    const wrapper = mountBoard({ groupBy: 'sdr' });
    const names = wrapper
      .findAll('[data-testid="swimlane-name"]')
      .map(n => n.text());
    expect(names).toEqual(['Edu', 'Ramon']);
  });

  it('re-emite move do cell com a etapa de destino', () => {
    const wrapper = mountBoard();
    wrapper
      .findComponent(SwimlaneCell)
      .vm.$emit('move', { id: 10, leadStageId: 2, newIndex: 0 });
    expect(wrapper.emitted().move[0][0]).toEqual({
      id: 10,
      leadStageId: 2,
      newIndex: 0,
    });
  });
});
