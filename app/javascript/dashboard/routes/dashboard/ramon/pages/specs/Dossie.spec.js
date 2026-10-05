import { mount, flushPromises } from '@vue/test-utils';
import Dossie from '../Dossie.vue';
import LeadsAPI from 'dashboard/api/leads';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1', leadId: '5' } }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
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
  passagem: {
    nome: 'Maria das Dores',
    cpf: '52998224725',
    contrato: { status: 'signed', assinado_em: '2026-10-04T15:00:00Z' },
    advbox: null,
    drive_url: null,
    cnis: null,
    simulacao: null,
    reuniao: null,
    prescription: { lost_installments: 0, months_to_cliff: 20 },
  },
  passagem_texto: 'DOSSIÊ DE PASSAGEM — Maria das Dores',
};

const mountDossie = async (extra = {}) => {
  LeadsAPI.getDossie.mockResolvedValue({ data: { ...payload, ...extra } });
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

  it('copia o texto único de passagem gerado no servidor', async () => {
    const wrapper = await mountDossie();
    await wrapper.find('[data-testid="dossie-copy"]').trigger('click');
    expect(copyTextToClipboard).toHaveBeenCalledWith(
      'DOSSIÊ DE PASSAGEM — Maria das Dores'
    );
  });

  it('mostra a passagem ao jurídico e o que falta sem quebrar', async () => {
    const wrapper = await mountDossie();
    const bloco = wrapper.find('[data-testid="ficha-passagem"]');
    expect(bloco.find('[data-testid="passagem-cpf"]').text()).toBe(
      '529.982.247-25'
    );
    expect(bloco.find('[data-testid="passagem-contrato"]').text()).toBe(
      'RAMON.FICHA.PASSAGEM.CONTRACT_SIGNED'
    );
    expect(bloco.find('[data-testid="passagem-advbox"]').text()).toBe(
      'RAMON.FICHA.PASSAGEM.ADVBOX_NONE'
    );
    expect(bloco.find('[data-testid="passagem-prescricao"]').text()).toBe(
      'RAMON.KANBAN.CARD.PRESCRIPTION_SOON'
    );
  });

  it('esconde a triagem quando não há registro concluído', async () => {
    const wrapper = await mountDossie({ triagem: null });
    expect(wrapper.find('[data-testid="dossie-triagem"]').exists()).toBe(false);
  });

  it('mostra o histórico completo aos poucos (ver mais)', async () => {
    const timeline = Array.from({ length: 25 }, (_, i) => ({
      type: 'activity',
      kind: 'stage_changed',
      to_value: `Etapa ${i}`,
      created_at: '2026-07-08T10:00:00Z',
    }));
    const wrapper = await mountDossie({ timeline });
    expect(wrapper.findAll('[data-testid="activity-row"]')).toHaveLength(20);
    await wrapper.find('[data-testid="dossie-timeline-more"]').trigger('click');
    expect(wrapper.findAll('[data-testid="activity-row"]')).toHaveLength(25);
    expect(wrapper.find('[data-testid="dossie-timeline-more"]').exists()).toBe(
      false
    );
  });
});
