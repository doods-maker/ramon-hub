import { mount, flushPromises } from '@vue/test-utils';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import RamonIaAtendimentoAPI from 'dashboard/api/ramonIaAtendimento';
import { dados } from 'dashboard/routes/dashboard/ramon/helpers/specs/perfilIaDados';
import ComoIaAtende from '../ComoIaAtende.vue';

vi.mock('vue-router', () => {
  const rota = { query: {} };
  return { useRoute: () => rota, onBeforeRouteLeave: vi.fn() };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));
vi.mock('dashboard/api/ramonIaAtendimento', () => ({
  default: { get: vi.fn(), salvar: vi.fn() },
}));

const montar = async () => {
  const wrapper = mount(ComoIaAtende, {
    global: {
      stubs: {
        RouterLink: {
          name: 'RouterLink',
          template: '<a><slot /></a>',
          props: ['to'],
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};
const achar = (wrapper, id) => wrapper.find(`[data-testid="${id}"]`);
const clicar = (wrapper, id) => achar(wrapper, id).trigger('click');
const permissao = (wrapper, acao) =>
  wrapper.find(`[data-testid="limite-${acao}"] [data-testid="permissao"]`);

describe('Como a IA atende', () => {
  beforeEach(() => {
    useRoute().query = {};
    RamonIaAtendimentoAPI.get.mockResolvedValue({ data: dados() });
  });

  it('escolher Acelerada troca o perfil; ajuste mostra o selo Personalizado e Desfazer volta', async () => {
    const wrapper = await montar();
    expect(achar(wrapper, 'selo').text()).toBe('Profile Balanced');

    await clicar(wrapper, 'perfil-acelerada');
    expect(achar(wrapper, 'selo').text()).toBe('Profile Fast');
    expect(achar(wrapper, 'alvo-padrao').text()).toContain('Fast');

    await achar(wrapper, 'marcador').trigger('keydown', { key: 'ArrowLeft' });
    expect(achar(wrapper, 'selo').text()).toBe(
      'Custom · based on Fast · 1 adjustment'
    );
    expect(achar(wrapper, 'alvo-padrao').text()).toContain(
      'Fast · 1 adjustment'
    );

    await clicar(wrapper, 'desfazer');
    expect(achar(wrapper, 'selo').text()).toBe('Profile Fast');
  });

  it('mover o Marcador com ArrowRight muda a frase e a etiqueta da Etapa', async () => {
    const wrapper = await montar();
    expect(achar(wrapper, 'frase').text()).toContain(
      'up to Reunião agendada. When the lead reaches Reunião realizada'
    );
    expect(achar(wrapper, 'etapa-fase-reuniao-realizada').text()).toContain(
      'Draft'
    );

    await achar(wrapper, 'marcador').trigger('keydown', { key: 'ArrowRight' });
    expect(achar(wrapper, 'frase').text()).toContain(
      'up to Reunião realizada. When the lead reaches Negociação'
    );
    expect(achar(wrapper, 'etapa-fase-reuniao-realizada').text()).toContain(
      'On its own'
    );
  });

  it('clicar na Permissão alterna Sozinha → Rascunho → Nunca e pula Nunca em logística', async () => {
    const wrapper = await montar();
    await clicar(wrapper, 'etapa-fase-qualificacao');
    const doc = () => permissao(wrapper, 'pedir_documentos');
    expect(doc().text()).toBe('On its own');
    await doc().trigger('click');
    expect(doc().text()).toBe('Draft');
    expect(
      wrapper
        .find(
          '[data-testid="limite-pedir_documentos"] [data-testid="ajustada"]'
        )
        .exists()
    ).toBe(true);
    await doc().trigger('click');
    expect(doc().text()).toBe('Never');
    await doc().trigger('click');
    expect(doc().text()).toBe('On its own');

    await clicar(wrapper, 'etapa-fase-reuniao-agendada');
    expect(achar(wrapper, 'limite-confirmacao').exists()).toBe(true);
    const log = () => permissao(wrapper, 'logistica');
    // antes do Marcador tudo sai sozinho: o ajuste aparece só na nota
    expect(log().text()).toBe('On its own');
    await log().trigger('click');
    expect(log().text()).toBe('On its own');
    expect(achar(wrapper, 'limite-logistica').text()).toContain(
      'before the marker everything goes out on its own (setting: Draft)'
    );

    // Marcador antes de Reunião agendada: logística vale a própria e pula Nunca
    await achar(wrapper, 'marcador').trigger('keydown', { key: 'ArrowLeft' });
    expect(log().text()).toBe('Draft');
    await log().trigger('click');
    expect(log().text()).toBe('On its own');
    await log().trigger('click');
    expect(log().text()).toBe('Draft');
  });

  it('depois do Marcador mostra o valor efetivo; desconto travado; gatilho pendente não liga', async () => {
    const wrapper = await montar();
    await clicar(wrapper, 'etapa-fase-negociacao');
    const contrato = () => achar(wrapper, 'limite-contrato_zapsign');
    expect(contrato().text()).not.toContain('limited by the marker');
    await permissao(wrapper, 'contrato_zapsign').trigger('click');
    await permissao(wrapper, 'contrato_zapsign').trigger('click');
    expect(permissao(wrapper, 'contrato_zapsign').text()).toBe('Draft');
    expect(contrato().text()).toContain(
      'limited by the marker (setting: On its own)'
    );
    expect(achar(wrapper, 'limite-desconto').text()).toContain(
      'Never · office rule'
    );
    expect(
      achar(wrapper, 'gatilho-irritado').attributes('disabled')
    ).toBeDefined();
    // pendente nunca chega ao prompt: desligado mesmo com a Equilibrada trazendo
    const irritado = achar(wrapper, 'gatilho-irritado');
    expect(irritado.text()).toContain('text pending');
    expect(irritado.attributes('aria-pressed')).toBe('false');
    expect(irritado.find('.i-lucide-check').exists()).toBe(false);

    await clicar(wrapper, 'gatilho-nao_le');
    expect(achar(wrapper, 'gatilho-nao_le').attributes('aria-pressed')).toBe(
      'true'
    );
    // contrato (1) + nao_le (1)
    expect(achar(wrapper, 'selo').text()).toContain('2 adjustments');
  });

  it('"Personalizar só esta" numa tese copia o padrão; "Voltar a seguir o padrão" desfaz', async () => {
    const wrapper = await montar();
    await clicar(wrapper, 'alvo-tese:1');
    expect(achar(wrapper, 'herda').text()).toContain('Balanced');
    expect(
      achar(wrapper, 'perfil-cautelosa').attributes('disabled')
    ).toBeDefined();
    expect(achar(wrapper, 'nao-salvas').exists()).toBe(false);

    await clicar(wrapper, 'personalizar');
    expect(achar(wrapper, 'herda').exists()).toBe(false);
    expect(achar(wrapper, 'selo').text()).toBe('Profile Balanced');
    expect(achar(wrapper, 'nao-salvas').text()).toBe('1 unsaved change');

    await clicar(wrapper, 'voltar-padrao');
    expect(achar(wrapper, 'herda').exists()).toBe(true);
    expect(achar(wrapper, 'nao-salvas').exists()).toBe(false);
  });

  it('"Salvar alterações" manda só os alvos mudados e recarrega da resposta', async () => {
    const resposta = dados();
    resposta.padrao = { base: 'cautelosa' };
    resposta.teses[0].cfg = { base: 'cautelosa' };
    RamonIaAtendimentoAPI.salvar.mockResolvedValue({ data: resposta });
    const wrapper = await montar();
    expect(achar(wrapper, 'salvar').attributes('disabled')).toBeDefined();

    await clicar(wrapper, 'perfil-cautelosa');
    await clicar(wrapper, 'alvo-tese:1');
    await clicar(wrapper, 'personalizar');
    expect(achar(wrapper, 'nao-salvas').text()).toBe('2 unsaved changes');

    await clicar(wrapper, 'salvar');
    await flushPromises();
    expect(RamonIaAtendimentoAPI.salvar).toHaveBeenCalledWith({
      padrao: { base: 'cautelosa' },
      teses: { 1: { base: 'cautelosa' } },
    });
    expect(achar(wrapper, 'nao-salvas').exists()).toBe(false);
    expect(achar(wrapper, 'selo').text()).toBe('Profile Cautious');
  });

  it('salvar troca Marcador velho e tira gatilhos de Etapa que saiu da Trilha', async () => {
    const corpo = dados();
    corpo.teses.push({
      id: 4,
      nome: 'Tese antiga',
      cfg: {
        base: 'equilibrada',
        marcador: 'fase-apagada',
        gatilhos: { 'fase-apagada': ['juridica'], 'fase-novo': ['juridica'] },
      },
    });
    RamonIaAtendimentoAPI.get.mockResolvedValue({ data: corpo });
    RamonIaAtendimentoAPI.salvar.mockResolvedValue({ data: corpo });
    const wrapper = await montar();
    await clicar(wrapper, 'alvo-tese:4');
    await clicar(wrapper, 'gatilho-pediu_pessoa');
    await clicar(wrapper, 'salvar');
    await flushPromises();
    expect(RamonIaAtendimentoAPI.salvar).toHaveBeenCalledWith({
      teses: {
        4: {
          base: 'equilibrada',
          marcador: '_inicio',
          gatilhos: { 'fase-novo': ['pediu_pessoa', 'juridica'] },
        },
      },
    });
  });

  it('erro 422 do salvar vira alerta com a mensagem do servidor', async () => {
    RamonIaAtendimentoAPI.salvar.mockRejectedValue({
      response: { data: { error: 'marcador desconhecido: x' } },
    });
    const wrapper = await montar();
    await clicar(wrapper, 'perfil-acelerada');
    await clicar(wrapper, 'salvar');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith('marcador desconhecido: x');
    expect(achar(wrapper, 'nao-salvas').text()).toBe('1 unsaved change');
  });

  it('limites gerais só no Padrão; editar conta como alteração e salvar manda os limites sem o teto do agente', async () => {
    const resposta = dados();
    resposta.limites.atraso = { min: 10, max: 60 };
    RamonIaAtendimentoAPI.salvar.mockResolvedValue({ data: resposta });
    const wrapper = await montar();
    expect(achar(wrapper, 'limites-gerais').exists()).toBe(true);
    expect(achar(wrapper, 'agente-dia').text()).toBe('30');
    expect(achar(wrapper, 'limites-gerais').text()).toContain(
      'changes on the VPS runner (CAP_DIA)'
    );

    await clicar(wrapper, 'alvo-tese:1');
    expect(achar(wrapper, 'limites-gerais').exists()).toBe(false);
    await clicar(wrapper, 'alvo-padrao');

    await achar(wrapper, 'dia-6').trigger('click');
    await achar(wrapper, 'atraso-min').setValue('10');
    await achar(wrapper, 'atraso-max').setValue('60');
    await achar(wrapper, 'lim-teto_usd').setValue('2.5');
    await achar(wrapper, 'segunda-faixa').trigger('click');
    expect(achar(wrapper, 'faixa-1-ini').exists()).toBe(false);
    expect(achar(wrapper, 'nao-salvas').text()).toBe('1 unsaved change');

    await clicar(wrapper, 'salvar');
    await flushPromises();
    expect(RamonIaAtendimentoAPI.salvar).toHaveBeenCalledWith({
      limites: {
        horario: { dias: [1, 2, 3, 4, 5, 6], janelas: [['08:30', '12:00']] },
        atraso: { min: 10, max: 60 },
        fluxo_ia_dia: 200,
        retomadas_dia: 15,
        retomada_intervalo_dias: 5,
        teto_usd: '2.5',
      },
    });
    expect(achar(wrapper, 'nao-salvas').exists()).toBe(false);
  });

  it('?alvo= abre o alvo pedido', async () => {
    useRoute().query = { alvo: 'tese:2' };
    const wrapper = await montar();
    expect(achar(wrapper, 'alvo-nome').text()).toBe('Auxílio-acidente');
    expect(achar(wrapper, 'selo').text()).toBe('Profile Fast');
  });
});
