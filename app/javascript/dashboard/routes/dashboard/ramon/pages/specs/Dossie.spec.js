import { mount, flushPromises } from '@vue/test-utils';
import Dossie from '../Dossie.vue';
import LeadsAPI from 'dashboard/api/leads';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

const mockRoute = { params: { accountId: '1', leadId: '5' }, query: {} };
const routerReplace = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => mockRoute,
  useRouter: () => ({ replace: routerReplace }),
}));
const storeDispatch = vi.fn().mockResolvedValue({});
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: storeDispatch }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false }),
}));
vi.mock('dashboard/api/leads', () => ({
  default: { getDossie: vi.fn(), portalLink: vi.fn(), update: vi.fn() },
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
    conversation_id: 77,
    profissao: 'metalúrgico',
    thesis_name: 'Auxílio-acidente',
    sdr: 'Sara',
    closer: null,
  },
  esteira: [
    { id: 1, name: 'Novo', color: '#475569', current: false },
    { id: 2, name: 'Negociação', color: '#0369A1', current: true },
    { id: 3, name: 'Ganhamos', color: '#15803D', is_won: true },
  ],
  docs: {
    received: 1,
    total: 2,
    itens: [
      { id: 11, title: 'RG e CPF', status: 'recebido' },
      { id: 12, title: 'Laudo', status: 'pendente' },
    ],
  },
  calculos: [],
  calculos_total: 0,
  reunioes: [],
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

const mountDossie = async (data = payload) => {
  LeadsAPI.getDossie.mockResolvedValue({ data });
  const wrapper = mount(Dossie, {
    global: {
      mocks: { $t: key => key },
      stubs: { RouterLink: true, LinhaDaVida: true, WonValueModal: true },
    },
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

  it('abas trocam, gravam ?aba= e respeitam a aba da URL', async () => {
    const wrapper = await mountDossie();
    expect(wrapper.find('[data-testid="dossie-timeline"]').exists()).toBe(true);
    await wrapper.find('[data-testid="ficha-aba-documentos"]').trigger('click');
    expect(routerReplace).toHaveBeenCalledWith({
      query: { aba: 'documentos' },
    });
    expect(wrapper.findAll('[data-testid="ficha-doc-item"]')).toHaveLength(2);
    expect(wrapper.find('[data-testid="dossie-timeline"]').exists()).toBe(
      false
    );

    mockRoute.query = { aba: 'calculos' };
    const outra = await mountDossie();
    expect(outra.find('[data-testid="dossie-calculos"]').exists()).toBe(true);
    mockRoute.query = {};
  });

  it('abas mostram as contagens de documentos e cálculos', async () => {
    const wrapper = await mountDossie();
    expect(
      wrapper.find('[data-testid="ficha-aba-documentos"]').text()
    ).toContain('1/2');
    expect(wrapper.find('[data-testid="ficha-aba-calculos"]').text()).toContain(
      '0'
    );
  });

  it('subtítulo traz tese, cidade e profissão; lateral o responsável', async () => {
    const wrapper = await mountDossie();
    expect(wrapper.text()).toContain(
      'Auxílio-acidente · Tubarão · metalúrgico'
    );
    expect(wrapper.find('[data-testid="dossie-pessoa"]').text()).toContain(
      'Sara'
    );
  });

  it('"Marcar como ganho" abre o modal de valor e salva na etapa de ganho', async () => {
    const wrapper = await mountDossie();
    await wrapper.find('[data-testid="ficha-marcar-ganho"]').trigger('click');
    const modal = wrapper.findComponent({ name: 'WonValueModal' });
    expect(modal.exists()).toBe(true);
    modal.vm.$emit('confirmValue', { value: 30000 });
    await flushPromises();
    expect(storeDispatch).toHaveBeenCalledWith('leads/update', {
      id: 5,
      lead_stage_id: 3,
      value: 30000,
    });
  });

  it('lead sem conversa, cálculo ou reunião: botão desabilitado e abas vazias sem erro', async () => {
    const vazio = {
      ...payload,
      pessoa: { ...payload.pessoa, conversation_id: null, contact_id: null },
      calculos: [],
      reunioes: [],
      docs: { received: 0, total: 0, itens: [] },
    };
    const wrapper = await mountDossie(vazio);
    expect(
      wrapper
        .find('[data-testid="ficha-open-conversation"]')
        .attributes('disabled')
    ).toBeDefined();
    const vaziaEm = async aba => {
      await wrapper.find(`[data-testid="ficha-aba-${aba}"]`).trigger('click');
      return wrapper.find('[data-testid="ficha-aba-vazia"]').exists();
    };
    expect(await vaziaEm('documentos')).toBe(true);
    expect(await vaziaEm('calculos')).toBe(true);
    expect(await vaziaEm('reunioes')).toBe(true);
    expect(await vaziaEm('linha_da_vida')).toBe(true);
  });
});
