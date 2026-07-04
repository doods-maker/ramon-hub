import { shallowMount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadKit from '../LeadKit.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const alertSpy = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...a) => alertSpy(...a),
}));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(),
}));
vi.mock('dashboard/api/leads', () => ({
  default: {
    getTriages: vi.fn(),
    createKit: vi.fn(),
  },
}));

const kitData = {
  resumo_leigo: 'Caso bom, vale a pena.',
  roteiro_perguntas: ['Você se machucou no trabalho?', 'Tem CAT emitida?'],
  documentos: [{ documento: 'CAT', porque: 'prova o acidente' }],
  venda_objecoes: {
    pitch: 'Vale a pena entrar com o pedido agora.',
    objecoes: [{ objecao: 'É caro?', resposta: 'Só paga no fim.' }],
  },
  proximo_passo: 'Assinar contrato e agendar reunião.',
};

const mountKit = lead =>
  shallowMount(LeadKit, {
    props: { lead },
    global: { mocks: { $t: k => k } },
  });

describe('LeadKit.vue', () => {
  beforeEach(() => {
    alertSpy.mockClear();
    copyTextToClipboard.mockClear();
    LeadsAPI.getTriages.mockReset();
    LeadsAPI.createKit.mockReset();
  });

  it('mostra o vazio quando não há triagem done', async () => {
    LeadsAPI.getTriages.mockResolvedValue({ data: [] });
    const wrapper = mountKit({ id: 3, stage_name: 'Qualificação' });
    await flushPromises();
    expect(wrapper.find('[data-testid="kit-empty"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="kit-generate"]').exists()).toBe(false);
  });

  it('gera o kit da triagem mais recente done', async () => {
    LeadsAPI.getTriages.mockResolvedValue({
      data: [
        { id: 11, status: 'done', kit_status: 'pending', kit: null },
      ],
    });
    LeadsAPI.createKit.mockResolvedValue({ data: {} });
    const wrapper = mountKit({ id: 3, stage_name: 'Qualificação' });
    await flushPromises();
    await wrapper.find('[data-testid="kit-generate"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.createKit).toHaveBeenCalledWith(3, 11);
    expect(alertSpy).toHaveBeenCalledWith('RAMON.KIT.STARTED');
  });

  it('renderiza só os blocos do modo sdr', async () => {
    LeadsAPI.getTriages.mockResolvedValue({
      data: [
        { id: 12, status: 'done', kit_status: 'ready', kit: kitData },
      ],
    });
    const wrapper = mountKit({ id: 3, stage_name: 'Qualificação' });
    await flushPromises();
    expect(wrapper.find('[data-testid="kit-block-roteiro"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="kit-block-proximo_passo"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="kit-block-resumo"]').exists()).toBe(
      false
    );
  });

  it('renderiza os blocos do modo closer', async () => {
    LeadsAPI.getTriages.mockResolvedValue({
      data: [
        { id: 13, status: 'done', kit_status: 'ready', kit: kitData },
      ],
    });
    const wrapper = mountKit({ id: 3, stage_name: 'Negociação' });
    await flushPromises();
    expect(wrapper.find('[data-testid="kit-block-resumo"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="kit-block-venda_objecoes"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kit-block-documentos"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kit-block-proximo_passo"]').exists()
    ).toBe(true);
  });

  it('não mostra nada além do aviso quando encerrado', async () => {
    LeadsAPI.getTriages.mockResolvedValue({ data: [] });
    const wrapper = mountKit({
      id: 3,
      stage_name: 'Fechado',
      won_at: '2026-07-01',
    });
    await flushPromises();
    const closed = wrapper.find('[data-testid="kit-closed"]');
    expect(closed.exists()).toBe(true);
    expect(closed.text()).toContain('RAMON.KIT.CLOSED');
    expect(wrapper.find('[data-testid="kit-generate"]').exists()).toBe(false);
  });

  it('copia o texto do bloco', async () => {
    LeadsAPI.getTriages.mockResolvedValue({
      data: [
        { id: 14, status: 'done', kit_status: 'ready', kit: kitData },
      ],
    });
    const wrapper = mountKit({ id: 3, stage_name: 'Qualificação' });
    await flushPromises();
    await wrapper.find('[data-testid="kit-copy-roteiro"]').trigger('click');
    await flushPromises();
    expect(copyTextToClipboard).toHaveBeenCalledWith(
      'Você se machucou no trabalho?\nTem CAT emitida?'
    );
  });

  it('recarrega quando latest_triage.kit_status muda', async () => {
    LeadsAPI.getTriages.mockResolvedValue({
      data: [
        { id: 20, status: 'done', kit_status: 'running', kit: null },
      ],
    });
    const wrapper = mountKit({
      id: 3,
      stage_name: 'Qualificação',
      latest_triage: { id: 20, status: 'done', kit_status: 'running' },
    });
    await flushPromises();
    expect(LeadsAPI.getTriages).toHaveBeenCalledTimes(1);

    LeadsAPI.getTriages.mockResolvedValue({
      data: [
        { id: 20, status: 'done', kit_status: 'ready', kit: kitData },
      ],
    });
    await wrapper.setProps({
      lead: {
        id: 3,
        stage_name: 'Qualificação',
        latest_triage: { id: 20, status: 'done', kit_status: 'ready' },
      },
    });
    await flushPromises();
    expect(LeadsAPI.getTriages).toHaveBeenCalledTimes(2);
  });
});
