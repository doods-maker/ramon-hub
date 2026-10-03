import { mount, flushPromises, RouterLinkStub } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import HojeComercial from '../HojeComercial.vue';
import SeloPrazo from '../SeloPrazo.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
const routerPush = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push: routerPush }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/api/leads', () => ({
  default: { followUpDraft: vi.fn() },
}));

const emFrente = minutos =>
  new Date(Date.now() + minutos * 60000).toISOString();

const sdr = (extra = {}) => ({
  papel: 'sdr',
  data: '2026-10-03',
  responder: [],
  follow_ups: [],
  reunioes: [],
  mes: { meta: null, contagem: 0, total: 0, contratos: 0 },
  ...extra,
});

const montar = dados =>
  mount(HojeComercial, {
    props: { dados },
    global: { stubs: { 'router-link': RouterLinkStub } },
  });

describe('HojeComercial', () => {
  beforeEach(() => vi.clearAllMocks());

  it('SDR: lead esperando aparece com o selo de prazo', () => {
    const w = montar(
      sdr({
        responder: [
          {
            lead_id: 1,
            nome: 'Rosane',
            tese: 'BPC/LOAS',
            canal: 'Indicação',
            conversa_id: 9,
            prazo_em: emFrente(3),
            ultima_mensagem: 'oi',
          },
        ],
      })
    );
    expect(w.text()).toContain('Rosane');
    expect(w.text()).toContain('BPC/LOAS · Indicação · “oi”');
    expect(w.findComponent(SeloPrazo).exists()).toBe(true);
    const responder = w
      .findAllComponents(RouterLinkStub)
      .find(l => l.text() === 'RAMON.HOJE.RESPONDER');
    expect(responder.props('to')).toEqual({
      name: 'inbox_conversation',
      params: { conversation_id: 9 },
    });
  });

  it('Preparar follow-up gera o rascunho e abre a conversa', async () => {
    LeadsAPI.followUpDraft.mockResolvedValue({});
    const w = montar(
      sdr({
        follow_ups: [
          {
            lead_id: 7,
            nome: 'Débora',
            tese: 'Auxílio-doença',
            titulo: 'ficou de mandar o CNIS',
            vence_em: emFrente(-60),
            conversa_id: 12,
          },
        ],
      })
    );
    await w.find('[data-testid="preparar-follow-up"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.followUpDraft).toHaveBeenCalledWith(7);
    expect(routerPush).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { conversation_id: 12 },
    });
  });

  it('listas vazias mostram os textos de vazio', () => {
    const w = montar(sdr());
    expect(w.text()).toContain('RAMON.HOJE.RESPONDER_VAZIO');
    expect(w.text()).toContain('RAMON.HOJE.FOLLOW_UPS_VAZIO');
    expect(w.text()).toContain('RAMON.HOJE.REUNIOES_MARCADAS_VAZIO');
  });

  it('Closer: reuniões de hoje com dossiê pronto quando os docs estão completos', () => {
    const w = montar({
      papel: 'closer',
      data: '2026-10-03',
      reunioes_hoje: [
        {
          quando: '2026-10-03T13:00:00Z',
          lead_id: 3,
          nome: 'Marlene',
          tese: 'Aposentadoria especial',
          docs: { received: 3, total: 3 },
        },
        {
          quando: '2026-10-03T17:00:00Z',
          lead_id: 4,
          nome: 'Valdir',
          tese: 'Trabalhista',
          docs: { received: 1, total: 3 },
        },
      ],
      assinatura: [],
      mes: { meta: 13, contagem: 9, total: 198, contratos: 9, fechamento: 41 },
    });
    expect(w.text()).toContain('RAMON.HOJE.REUNIOES_HOJE');
    expect(w.text()).toContain('10:00');
    expect(w.text()).toContain('RAMON.HOJE.DOSSIE_PRONTO');
    expect(w.text()).toContain('RAMON.HOJE.FALTAM_DOCS');
    expect(w.text()).toContain('41%');
    expect(w.text()).toContain('RAMON.HOJE.ASSINATURA_VAZIO');
    expect(w.text()).not.toContain('RAMON.HOJE.RESPONDER_AGORA');
  });
});
