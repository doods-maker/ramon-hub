import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import RamonPeticoesAPI from 'dashboard/api/ramonPeticoes';
import ConferenciaPasta from '../ConferenciaPasta.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k, p) => `${k}${p?.detalhe ? `|${p.detalhe}` : ''}` }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: key => ref(key === 'agents/getAgents' ? [] : 1),
}));
vi.mock('dashboard/api/contacts', () => ({ default: { search: vi.fn() } }));
vi.mock('dashboard/api/ramonPeticoes', () => ({
  default: {
    show: vi.fn(),
    update: vi.fn(),
    confirmar: vi.fn(),
    relerPasta: vi.fn(),
    processos: vi.fn(() => Promise.resolve({ data: { processos: [] } })),
  },
}));

const peticao = (extra = {}, leitura = {}) => ({
  id: 7,
  status: 'conferencia',
  pela_pasta: true,
  inicial: false,
  numero_processo: '',
  contato: null,
  responsavel: { id: 1, name: 'Ana' },
  arquivos: [],
  problemas: [],
  alertas: [],
  avisos: [],
  leitura: { estado: 'lida', recusas: [], incertos: [], ...leitura },
  ...extra,
});

const montar = p => mount(ConferenciaPasta, { props: { peticao: p } });
const confirmar = w => w.find('[data-testid="conferencia-confirmar"]');

describe('ConferenciaPasta.vue', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
  });
  afterEach(() => vi.useRealTimers());

  it('recusa traduzida em bloco e Confirmar travado', () => {
    const w = montar(peticao({}, { recusas: ['marcador:[CONFERIR]'] }));
    expect(w.find('[data-testid="conferencia-recusas"]').text()).toContain(
      'RAMON.PETICOES.PASTA.RECUSA.marcador|[CONFERIR]'
    );
    expect(confirmar(w).attributes('disabled')).toBeDefined();
  });

  it('alerta só libera Confirmar depois de marcado', async () => {
    const w = montar(peticao({ alertas: ['cpf_diferente'] }));
    expect(confirmar(w).attributes('disabled')).toBeDefined();
    await w
      .find('[data-testid="conferencia-alerta-cpf_diferente"]')
      .setValue(true);
    expect(confirmar(w).attributes('disabled')).toBeUndefined();
  });

  it('confirmar salva e depois confirma, avisando os alertas conferidos', async () => {
    RamonPeticoesAPI.update.mockResolvedValue({ data: {} });
    RamonPeticoesAPI.confirmar.mockResolvedValue({
      data: { id: 7, status: 'rascunho' },
    });
    const w = montar(peticao({ alertas: ['cpf_diferente'] }));
    await w
      .find('[data-testid="conferencia-alerta-cpf_diferente"]')
      .setValue(true);
    await confirmar(w).trigger('click');
    await flushPromises();
    expect(RamonPeticoesAPI.update).toHaveBeenCalledWith(7, expect.any(Object));
    expect(RamonPeticoesAPI.confirmar).toHaveBeenCalledWith(7, true);
    expect(w.emitted('confirmado')[0][0].status).toBe('rascunho');
  });

  it('lendo: consulta a cada 3 s e para ao desmontar', async () => {
    RamonPeticoesAPI.show.mockResolvedValue({ data: peticao({}, {}) });
    const w = montar(peticao({}, { estado: 'lendo' }));
    expect(w.find('[data-testid="conferencia-lendo"]').exists()).toBe(true);
    await vi.advanceTimersByTimeAsync(3000);
    expect(RamonPeticoesAPI.show).toHaveBeenCalledTimes(1);
    expect(w.emitted('atualizado')).toHaveLength(1);
    w.unmount();
    await vi.advanceTimersByTimeAsync(10000);
    expect(RamonPeticoesAPI.show).toHaveBeenCalledTimes(1);
  });

  it('erro de leitura: mostra Reler e não oferece Confirmar', () => {
    const w = montar(peticao({}, { estado: 'erro' }));
    expect(w.find('[data-testid="conferencia-erro"]').exists()).toBe(true);
    expect(confirmar(w).exists()).toBe(false);
  });

  it('falha ao salvar não chama confirmar', async () => {
    RamonPeticoesAPI.update.mockRejectedValue({
      response: { data: { errors: ['Número inválido'] } },
    });
    const w = montar(peticao());
    await confirmar(w).trigger('click');
    await flushPromises();
    expect(RamonPeticoesAPI.confirmar).not.toHaveBeenCalled();
    expect(w.find('[data-testid="conferencia-erro-acao"]').text()).toContain(
      'Número inválido'
    );
  });

  it('responsável incerto: checkbox obrigatório para confirmar', async () => {
    const w = montar(peticao({}, { incertos: ['responsavel'] }));
    expect(confirmar(w).attributes('disabled')).toBeDefined();
    await w.find('[data-testid="conferencia-responsavel"]').setValue(true);
    expect(confirmar(w).attributes('disabled')).toBeUndefined();
  });

  it('mostra os problemas do pacote', () => {
    const w = montar(peticao({ problemas: ['sem_principal'] }));
    expect(w.find('[data-testid="conferencia-problemas"]').text()).toContain(
      'RAMON.PETICOES.PROBLEMAS.SEM_PRINCIPAL'
    );
  });

  it('pacote novo (mesmo id e estado) não apaga o que foi digitado', async () => {
    const w = montar(peticao());
    const campo = w.find('[data-testid="peticao-form-numero"]');
    await campo.setValue('0001234-56.2026.8.24.0001');
    await w.setProps({ peticao: peticao({ arquivos: [{ id: 1 }] }) });
    expect(w.find('[data-testid="peticao-form-numero"]').element.value).toBe(
      '0001234-56.2026.8.24.0001'
    );
  });

  it('reler com sucesso limpa as marcações de conferido', async () => {
    RamonPeticoesAPI.relerPasta.mockResolvedValue({
      data: peticao({ alertas: ['cpf_diferente'] }),
    });
    const w = montar(peticao({ alertas: ['cpf_diferente'] }));
    await w
      .find('[data-testid="conferencia-alerta-cpf_diferente"]')
      .setValue(true);
    expect(confirmar(w).attributes('disabled')).toBeUndefined();
    await w.find('[data-testid="conferencia-reler"]').trigger('click');
    await flushPromises();
    await w.setProps({ peticao: w.emitted('atualizado')[0][0] });
    expect(confirmar(w).attributes('disabled')).toBeDefined();
  });

  it('volta a lendo: marcações são limpas', async () => {
    const w = montar(peticao({ alertas: ['cpf_diferente'] }));
    await w
      .find('[data-testid="conferencia-alerta-cpf_diferente"]')
      .setValue(true);
    await w.setProps({
      peticao: peticao({ alertas: ['cpf_diferente'] }, { estado: 'lendo' }),
    });
    await w.setProps({ peticao: peticao({ alertas: ['cpf_diferente'] }) });
    expect(confirmar(w).attributes('disabled')).toBeDefined();
  });
});
