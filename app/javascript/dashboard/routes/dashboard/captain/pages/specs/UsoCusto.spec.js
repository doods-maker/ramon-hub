import { mount, flushPromises } from '@vue/test-utils';
import RamonIaUsoAPI from 'dashboard/api/ramonIaUso';
import CaptainPreferencesAPI from 'dashboard/api/captain/preferences';
import UsoCusto from '../UsoCusto.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/ramonIaUso', () => ({
  default: { get: vi.fn(), salvarTeto: vi.fn() },
}));
vi.mock('dashboard/api/captain/preferences', () => ({
  default: { updatePreferences: vi.fn() },
}));

const MODELOS = [
  { id: 'deepseek-chat', display_name: 'DeepSeek Chat', provider: 'deepseek' },
  { id: 'gpt-4.1-mini', display_name: 'GPT-4.1 Mini', provider: 'openai' },
  {
    id: 'claude-haiku-4-5',
    display_name: 'Claude Haiku 4.5',
    provider: 'anthropic',
  },
];

const DADOS = {
  periodo: '7d',
  total: {
    chamadas: 120,
    input_tokens: 900000,
    output_tokens: 80000,
    custo_usd: 1.75,
    erros: 2,
    sem_preco: 1,
  },
  por_dia: [
    { dia: '2026-10-05', custo_usd: 0.5, chamadas: 40 },
    { dia: '2026-10-06', custo_usd: 1.25, chamadas: 80 },
  ],
  por_funcao: [
    {
      chave: 'atendimento',
      chamadas: 80,
      input_tokens: 700000,
      output_tokens: 60000,
      custo_usd: 1.25,
      erros: 0,
    },
    {
      chave: 'copiloto',
      chamadas: 40,
      input_tokens: 200000,
      output_tokens: 20000,
      custo_usd: 0.5,
      erros: 2,
    },
  ],
  por_assistente: [],
  por_modelo: [],
  hoje_usd: 1.25,
  teto_diario_usd: 1,
  agente: { hoje: 4, teto: 30, custo_periodo_usd: 3.2 },
  fluxos: { hoje: 12, teto: 200 },
  chaves: { deepseek: true, openai: false, anthropic: true, claude_vps: true },
  escolhas: [
    {
      funcao: 'atendimento',
      feature: 'assistant',
      fonte: 'reserva',
      salvo: null,
      provider: 'deepseek',
      model: 'deepseek-v4-pro',
      modelos: MODELOS,
    },
    {
      funcao: 'copiloto',
      feature: 'copilot',
      fonte: 'tela',
      salvo: 'deepseek-chat',
      provider: 'deepseek',
      model: 'deepseek-chat',
      modelos: MODELOS,
    },
    {
      funcao: 'agente',
      feature: null,
      fonte: 'reserva',
      salvo: null,
      provider: 'claude_vps',
      model: 'claude-vps',
      modelos: [],
    },
  ],
};

const montar = async () => {
  const wrapper = mount(UsoCusto);
  await flushPromises();
  return wrapper;
};

describe('Uso e custo da IA', () => {
  beforeEach(() => {
    RamonIaUsoAPI.get.mockResolvedValue({ data: DADOS });
    RamonIaUsoAPI.salvarTeto.mockResolvedValue({ data: {} });
    CaptainPreferencesAPI.updatePreferences.mockResolvedValue({ data: {} });
  });

  it('mostra o custo do período, o estouro do teto e a tabela por função', async () => {
    const wrapper = await montar();

    expect(RamonIaUsoAPI.get).toHaveBeenCalledWith({ periodo: '7d' });
    expect(wrapper.find('[data-testid="uso-custo"]').text()).toContain(
      'US$ 1,75'
    );
    expect(wrapper.find('[data-testid="uso-hoje"] p').classes()).toContain(
      'text-n-ruby-11'
    );
    expect(wrapper.findAll('[data-testid="uso-grafico"] rect')).toHaveLength(2);
    const linhas = wrapper.findAll('[data-testid="uso-tabela"] tbody tr');
    expect(linhas.map(linha => linha.find('td').text())).toEqual([
      'Customer service',
      'Copilot',
    ]);
  });

  it('troca o período e busca de novo', async () => {
    const wrapper = await montar();
    const abas = wrapper.findAll('[data-testid="uso-periodos"] button');

    await abas[0].trigger('click');

    expect(RamonIaUsoAPI.get).toHaveBeenLastCalledWith({ periodo: 'hoje' });
  });

  it('assinatura do Claude só no agente: fixa, sem seletor, e aviso na tela', async () => {
    const wrapper = await montar();
    const agente = wrapper.find('[data-testid="escolha-agente"]');

    expect(agente.find('select').exists()).toBe(false);
    expect(agente.text()).toContain('Claude on the VPS (subscription)');
    const provedores = wrapper
      .find('[data-testid="escolha-copiloto"] [data-testid="select-provedor"]')
      .findAll('option');
    expect(provedores.map(opcao => opcao.attributes('value'))).toEqual([
      'deepseek',
      'openai',
      'anthropic',
    ]);
    expect(provedores[1].attributes('disabled')).toBeDefined();
    expect(wrapper.find('[data-testid="aviso-assinatura"]').text()).toContain(
      "manager's internal use"
    );
  });

  it('trocar provedor filtra os modelos e salvar manda o modelo da feature', async () => {
    const wrapper = await montar();
    const linha = wrapper.find('[data-testid="escolha-atendimento"]');

    await linha.find('[data-testid="select-provedor"]').setValue('anthropic');
    const modelo = linha.find('[data-testid="select-modelo"]');
    expect(modelo.findAll('option').map(o => o.attributes('value'))).toEqual([
      '',
      'claude-haiku-4-5',
    ]);
    await modelo.setValue('claude-haiku-4-5');
    await flushPromises();

    expect(CaptainPreferencesAPI.updatePreferences).toHaveBeenCalledWith({
      captain_models: { assistant: 'claude-haiku-4-5' },
    });
    expect(RamonIaUsoAPI.get).toHaveBeenCalledTimes(2);
  });

  it('salva o teto do alerta de gasto', async () => {
    const wrapper = await montar();

    await wrapper.find('[data-testid="input-teto"]').setValue('2.5');
    await wrapper.find('[data-testid="salvar-teto"]').trigger('click');
    await flushPromises();

    expect(RamonIaUsoAPI.salvarTeto).toHaveBeenCalledWith(2.5);
  });
});
