import { mount, flushPromises } from '@vue/test-utils';
import Dossie from '../Dossie.vue';
import LeadsAPI from 'dashboard/api/leads';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1', leadId: '5' } }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false }),
}));
vi.mock('dashboard/api/leads', () => ({
  default: { getDossie: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn().mockResolvedValue(),
}));

const payload = {
  pessoa: {
    lead_id: 5,
    lead_name: 'Maria das Dores',
    contact_name: 'Maria das Dores',
    phone_number: '+5548999990000',
    idade: 42,
    cidade: 'Tubarão',
    stage_name: 'Negociação',
    stage_color: '#aa8844',
    value: 25000,
    consent_marketing: true,
  },
  origem: {
    source: 'anuncio-meta-auxilio',
    channel: 'meta_ads',
    channel_label: 'Meta Ads',
    utm: { utm_campaign: 'aux-acidente' },
    indicacao: false,
  },
  triagem: {
    id: 9,
    status: 'done',
    viability: null,
    awaiting_human: true,
    result: 'Caso com indícios de nexo.',
  },
  tese: {
    id: 1,
    name: 'Auxílio-acidente',
    honorario_text: '30% dos atrasados + 3 mensalidades',
    objecoes: [{ title: 'É caro', content: 'Só paga se ganhar.' }],
  },
  timeline: [
    {
      type: 'note',
      body: 'Cliente vai pensar',
      author_name: 'Eduardo',
      created_at: '2026-07-08T10:00:00Z',
    },
  ],
  pendencias: {
    tasks: [
      { id: 1, title: 'Confirmar reunião', due_at: '2026-07-10T10:00:00Z' },
    ],
    docs_missing: [{ title: 'Laudo', status: 'pendente' }],
  },
};

const mountDossie = async () => {
  LeadsAPI.getDossie.mockResolvedValue({ data: payload });
  const wrapper = mount(Dossie, {
    global: { mocks: { $t: key => key }, stubs: { RouterLink: true } },
  });
  await flushPromises();
  return wrapper;
};

describe('Dossie.vue', () => {
  it('busca o dossiê do lead da rota e renderiza os blocos', async () => {
    const wrapper = await mountDossie();
    expect(LeadsAPI.getDossie).toHaveBeenCalledWith('5');
    expect(wrapper.find('[data-testid="dossie-pessoa"]').text()).toContain(
      'Tubarão'
    );
    expect(wrapper.find('[data-testid="dossie-origem"]').text()).toContain(
      'Meta Ads'
    );
    expect(wrapper.find('[data-testid="dossie-honorario"]').text()).toContain(
      '30% dos atrasados + 3 mensalidades'
    );
    expect(wrapper.findAll('[data-testid="dossie-objecao"]')).toHaveLength(1);
    expect(wrapper.findAll('[data-testid="dossie-doc"]')).toHaveLength(1);
  });

  it('sinaliza triagem aguardando revisão humana', async () => {
    const wrapper = await mountDossie();
    expect(wrapper.find('[data-testid="dossie-awaiting-human"]').exists()).toBe(
      true
    );
  });

  it('copia o dossiê em markdown', async () => {
    const wrapper = await mountDossie();
    await wrapper.find('[data-testid="dossie-copy"]').trigger('click');
    expect(copyTextToClipboard).toHaveBeenCalled();
    const markdown = copyTextToClipboard.mock.calls[0][0];
    expect(markdown).toContain('Maria das Dores');
    expect(markdown).toContain('30% dos atrasados + 3 mensalidades');
    expect(markdown).toContain('- [ ] Confirmar reunião');
  });
});
