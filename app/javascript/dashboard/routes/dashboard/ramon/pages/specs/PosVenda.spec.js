import { mount, flushPromises } from '@vue/test-utils';
import PosVenda from '../PosVenda.vue';
import RamonPosVendaAPI from 'dashboard/api/ramonPosVenda';
import LeadsAPI from 'dashboard/api/leads';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

const t = (key, params) =>
  params ? `${key} ${Object.values(params).join(' ')}` : key;
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));

const routerPush = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push: routerPush }) }));

const dispatchSpy = vi.fn();
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: dispatchSpy }),
}));

const alertSpy = vi.fn();
vi.mock('dashboard/composables', () => ({ useAlert: msg => alertSpy(msg) }));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));

vi.mock('shared/helpers/clipboard', () => ({ copyTextToClipboard: vi.fn() }));
vi.mock('dashboard/api/ramonPosVenda', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/leads', () => ({ default: { update: vi.fn() } }));

const pendente = (id, conversationId) => ({
  id,
  name: `Cliente ${id}`,
  lead_name: `Lead ${id}`,
  dias: 9,
  docs_received: 1,
  docs_total: 3,
  conversation_id: conversationId,
  docs_pendentes: [
    { id: 7, title: 'RG e CPF', status: 'pendente' },
    { id: 8, title: 'Laudo médico', status: 'solicitado' },
  ],
});

const mountPage = async (data = {}) => {
  RamonPosVendaAPI.get.mockResolvedValue({
    data: {
      pendentes: [pendente(1, 501), pendente(2, null)],
      concluidos: [{ id: 9, name: 'Concluído' }],
      concluidos_total: 35,
      sem_tese: [{ id: 3, name: 'Sem Tese', dias: 4 }],
      ...data,
    },
  });
  const wrapper = mount(PosVenda, { global: { mocks: { $t: t } } });
  await flushPromises();
  return wrapper;
};

describe('PosVenda.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    LeadsAPI.update.mockResolvedValue({});
  });

  it('lista o que falta em cada pendente', async () => {
    const wrapper = await mountPage();
    const docs = wrapper.findAll('[data-testid="pos-venda-docs-pendentes"]');
    expect(docs[0].text()).toContain('RG e CPF');
    expect(docs[0].text()).toContain('Laudo médico');
  });

  it('Cobrar pendentes com conversa: rascunho no campo de resposta, abre o dock e marca só os pendentes', async () => {
    const wrapper = await mountPage();
    await wrapper
      .findAll('[data-testid="pos-venda-cobrar"]')[0]
      .trigger('click');
    await flushPromises();

    const [, draft] = dispatchSpy.mock.calls.find(
      ([action]) => action === 'draftMessages/set'
    );
    expect(draft.key).toBe('draft-501-REPLY');
    expect(draft.message).toContain('RAMON.DOCS.DRAFT.GREETING Lead 1');
    expect(draft.message).toContain('RAMON.DOCS.DRAFT.ITEM RG e CPF');
    expect(dispatchSpy).toHaveBeenCalledWith('leads/toggleDock', 501);
    expect(LeadsAPI.update).toHaveBeenCalledWith(1, {
      custom_attributes: { doc_status: { 7: 'solicitado' } },
    });
    expect(alertSpy).toHaveBeenCalledWith('RAMON.DOCS.DRAFT_READY');
  });

  it('Cobrar pendentes sem conversa: copia o rascunho (como o painel na gaveta)', async () => {
    const wrapper = await mountPage();
    await wrapper
      .findAll('[data-testid="pos-venda-cobrar"]')[1]
      .trigger('click');
    await flushPromises();

    expect(copyTextToClipboard).toHaveBeenCalledWith(
      expect.stringContaining('RAMON.DOCS.DRAFT.CLOSING')
    );
    expect(alertSpy).toHaveBeenCalledWith('RAMON.DOCS.COPIED');
    expect(dispatchSpy).not.toHaveBeenCalledWith(
      'draftMessages/set',
      expect.anything()
    );
  });

  it('mostra os ganhos sem tese e o total real de concluídos', async () => {
    const wrapper = await mountPage();
    expect(wrapper.find('[data-testid="pos-venda-sem-tese"]').text()).toContain(
      'RAMON.POS_VENDA.SEM_TESE 1'
    );
    const toggle = wrapper.find('[data-testid="pos-venda-toggle-concluidos"]');
    expect(toggle.text()).toContain('RAMON.POS_VENDA.CONCLUIDOS 35');
    await toggle.trigger('click');
    expect(
      wrapper.find('[data-testid="pos-venda-concluidos-recentes"]').exists()
    ).toBe(true);
  });
});
