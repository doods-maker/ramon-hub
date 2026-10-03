import { mount, flushPromises } from '@vue/test-utils';
import RamonPrescriptionRadarAPI from 'dashboard/api/ramonPrescriptionRadar';
import RamonPosVendaAPI from 'dashboard/api/ramonPosVenda';
import FaixaFiltro from '../FaixaFiltro.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (k, v) => (v ? `${k} ${JSON.stringify(v)}` : k),
  }),
}));
const routerPush = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push: routerPush }) }));
const dispatch = vi.fn();
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));
vi.mock('dashboard/api/ramonPrescriptionRadar', () => ({
  default: { get: vi.fn() },
}));
vi.mock('dashboard/api/ramonPosVenda', () => ({ default: { get: vi.fn() } }));

const montar = (props = {}) =>
  mount(FaixaFiltro, {
    props: { filtro: 'prescricao', ...props },
    global: { mocks: { $t: k => k } },
  });

describe('FaixaFiltro', () => {
  beforeEach(() => {
    routerPush.mockClear();
    dispatch.mockClear();
    RamonPrescriptionRadarAPI.get.mockResolvedValue({
      data: {
        summary: {
          bleeding_monthly: 2800,
          bleeding_count: 2,
          at_risk_90d_monthly: 1400,
          at_risk_90d_count: 1,
        },
        items: [
          { lead_id: 1, consent_marketing: true },
          { lead_id: 2, consent_marketing: false },
          { lead_id: 3, consent_marketing: true },
        ],
      },
    });
    RamonPosVendaAPI.get.mockResolvedValue({
      data: {
        pendentes: [{ id: 5 }],
        concluidos: [
          { id: 6, name: 'Ivone', drive_concluido: true },
          { id: 7, name: 'Paulo', drive_concluido: false },
        ],
      },
    });
  });

  it('radar: resumo e campanha de resgate só com consentidos, via ConfirmModal', async () => {
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-testid="faixa-sangrando"]').text()).toContain(
      '"count":2'
    );
    expect(wrapper.text()).toContain('"n":2,"m":3');
    await wrapper.find('[data-testid="faixa-campanha"]').trigger('click');
    const modal = wrapper.findComponent({ name: 'ConfirmModal' });
    expect(routerPush).not.toHaveBeenCalled();
    modal.vm.$emit('confirm');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'campaigns_whatsapp_index',
    });
  });

  it('pós-venda: resumo e Concluídos recolhível com chip do Drive', async () => {
    const wrapper = montar({ filtro: 'pos_venda' });
    await flushPromises();
    expect(wrapper.find('[data-testid="faixa-pos-venda"]').text()).toContain(
      '"count":1'
    );
    expect(wrapper.findAll('[data-testid="faixa-concluido"]')).toHaveLength(0);
    await wrapper.find('[data-testid="faixa-concluidos"]').trigger('click');
    expect(wrapper.findAll('[data-testid="faixa-concluido"]')).toHaveLength(2);
    expect(wrapper.findAll('[data-testid="faixa-drive"]')).toHaveLength(1);
    await wrapper
      .find('[data-testid="faixa-concluido"] button')
      .trigger('click');
    expect(dispatch).toHaveBeenCalledWith('leads/select', 6);
  });

  it('com outros filtros ligados oferece limpar', async () => {
    const wrapper = montar({ outrosFiltros: true });
    await flushPromises();
    await wrapper.find('[data-testid="faixa-limpar"]').trigger('click');
    expect(wrapper.emitted('limparFiltros')).toHaveLength(1);
  });
});
