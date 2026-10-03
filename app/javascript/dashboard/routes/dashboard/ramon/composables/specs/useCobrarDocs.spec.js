import LeadsAPI from 'dashboard/api/leads';
import { useCobrarDocs } from '../useCobrarDocs';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
const dispatch = vi.fn();
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
const alerta = vi.fn();
vi.mock('dashboard/composables', () => ({ useAlert: (...a) => alerta(...a) }));
vi.mock('dashboard/api/leads', () => ({ default: { show: vi.fn() } }));

describe('useCobrarDocs', () => {
  beforeEach(() => {
    dispatch.mockReset();
    alerta.mockReset();
  });

  it('lista os documentos da tese que faltam, com o status do lead', async () => {
    LeadsAPI.show.mockResolvedValue({
      data: {
        thesis_id: 4,
        custom_attributes: { doc_status: { 1: 'recebido', 2: 'solicitado' } },
      },
    });
    dispatch.mockResolvedValue({
      items: [
        { id: 1, section: 'documento', title: 'RG' },
        { id: 2, section: 'documento', title: 'CAT' },
        { id: 3, section: 'documento', title: '', content: 'Laudos' },
        { id: 4, section: 'objecao', title: 'É caro' },
      ],
    });
    const itens = await useCobrarDocs().pendentesDoLead(10);
    expect(dispatch).toHaveBeenCalledWith('theses/show', 4);
    expect(itens).toEqual([
      { id: 2, title: 'CAT', status: 'solicitado' },
      { id: 3, title: 'Laudos', status: 'pendente' },
    ]);
  });

  it('lead sem tese não tem o que cobrar', async () => {
    LeadsAPI.show.mockResolvedValue({ data: { thesis_id: null } });
    expect(await useCobrarDocs().pendentesDoLead(10)).toEqual([]);
  });

  it('marca só os pendentes como solicitados, pelo store; erro vira aviso', async () => {
    const { marcarSolicitados } = useCobrarDocs();
    await marcarSolicitados(10, [
      { id: 2, status: 'solicitado' },
      { id: 3, status: 'pendente' },
    ]);
    expect(dispatch).toHaveBeenCalledWith('leads/update', {
      id: 10,
      custom_attributes: { doc_status: { 3: 'solicitado' } },
    });
    dispatch.mockRejectedValueOnce(new Error('x'));
    await marcarSolicitados(10, [{ id: 3, status: 'pendente' }]);
    expect(alerta).toHaveBeenCalledWith('RAMON.FUNIL.SAVE_ERROR');
  });
});
