import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadHistory from '../LeadHistory.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: k => k, te: () => true }),
}));

const atividade = (id, kind, extra = {}) => ({
  id,
  kind,
  from_value: null,
  to_value: null,
  author_name: 'Ana',
  created_at: `2026-06-0${id}T10:00:00Z`,
  ...extra,
});
const activities = [
  atividade(1, 'created', { to_value: 'instagram', author_name: null }),
  atividade(2, 'stage_changed', {
    from_value: 'Novo',
    to_value: 'Qualificação',
  }),
];
const build = fetchSpy =>
  createStore({
    modules: {
      leads: { namespaced: true, actions: { fetchActivities: fetchSpy } },
      leadConfig: {
        namespaced: true,
        getters: {
          getStages: () => [
            { id: 1, name: 'Novo', color: '#3b82f6' },
            { id: 2, name: 'Qualificação', color: '#8b5cf6' },
            { id: 3, name: 'Fechado', color: '#22c55e', is_won: true },
            { id: 4, name: 'Perdido', color: '#ef4444', is_lost: true },
          ],
        },
      },
    },
  });
const mountHistory = (fetchSpy = vi.fn().mockResolvedValue(activities)) =>
  shallowMount(LeadHistory, {
    props: { leadId: 7 },
    global: {
      plugins: [build(fetchSpy)],
      mocks: { $t: k => k },
      // as linhas vivem na ListaAtividades (compartilhada com o Dossiê)
      stubs: { ListaAtividades: false },
    },
  });
const linhas = async lista => {
  const wrapper = mountHistory(vi.fn().mockResolvedValue(lista));
  await flushPromises();
  return wrapper.findAll('[data-testid="activity-row"]');
};

it('fetches activities on mount', async () => {
  const fetchSpy = vi.fn().mockResolvedValue(activities);
  mountHistory(fetchSpy);
  await flushPromises();
  expect(fetchSpy).toHaveBeenCalledWith(expect.anything(), 7);
});

it('renders one row per activity, most recent first, under "Atividade recente"', async () => {
  const wrapper = mountHistory();
  await flushPromises();
  expect(wrapper.text()).toContain('RAMON.LEAD_PANEL.HISTORY.TITLE');
  const rows = wrapper.findAll('[data-testid="activity-row"]');
  expect(rows).toHaveLength(2);
  expect(rows[0].text()).toContain('Qualificação'); // ordem invertida = mais recente no topo
  // sem autor = Sistema
  expect(rows[1].text()).toContain('RAMON.LEAD_PANEL.HISTORY.SYSTEM');
});

it.each([
  [
    'stage_changed',
    { to_value: 'Qualificação' },
    'etapa',
    'i-lucide-arrow-right',
    'text-n-blue-11',
  ],
  [
    'stage_changed',
    { to_value: 'Fechado' },
    'ganho',
    'i-lucide-trophy',
    'text-n-teal-11',
  ],
  [
    'stage_changed',
    { to_value: 'Perdido' },
    'perda',
    'i-lucide-x',
    'text-n-ruby-11',
  ],
  [
    'note_added',
    { to_value: 'Ligou' },
    'nota',
    'i-lucide-file-text',
    'text-n-slate-11',
  ],
  [
    'value_changed',
    { to_value: '18500' },
    'campo',
    'i-lucide-plus',
    'text-n-teal-11',
  ],
  [
    'closer_changed',
    { to_value: 'Camila' },
    'dono',
    'i-lucide-user',
    'text-n-iris-11',
  ],
  ['meeting_scheduled', {}, 'reuniao', 'i-lucide-calendar', 'text-n-amber-11'],
  ['esteira_done', {}, 'outro', 'i-lucide-dot', 'text-n-slate-11'],
])('%s %o → ícone %s', async (kind, extra, grupo, icone, cor) => {
  const [linha] = await linhas([atividade(1, kind, extra)]);
  const icon = linha.find('[data-testid="activity-icon"]');
  expect(icon.attributes('data-grupo')).toBe(grupo);
  expect(icon.classes()).toContain(cor);
  expect(icon.find('span').classes()).toContain(icone);
});

it('etapa: "Etapa: A → B" com B na cor da etapa', async () => {
  const [linha] = await linhas([
    atividade(1, 'stage_changed', {
      from_value: 'Novo',
      to_value: 'Qualificação',
    }),
  ]);
  const detalhe = linha.find('[data-testid="activity-detail"]');
  expect(detalhe.text()).toBe(
    'RAMON.LEAD_PANEL.HISTORY.DETAIL.STAGE: Novo → Qualificação'
  );
  expect(
    linha.find('[data-testid="activity-para"]').attributes('style')
  ).toContain('color: rgb(139, 92, 246)');
});

it('nota: trecho em itálico, entre aspas', async () => {
  const [linha] = await linhas([
    atividade(1, 'note_added', { to_value: 'Verificar documentos' }),
  ]);
  const detalhe = linha.find('[data-testid="activity-detail"]');
  expect(detalhe.find('.italic').text()).toBe('“Verificar documentos”');
});

it('sem atividade: linha de vazio', async () => {
  const wrapper = mountHistory(vi.fn().mockResolvedValue([]));
  await flushPromises();
  expect(wrapper.find('[data-testid="history-empty"]').exists()).toBe(true);
});
