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
    expect(log().text()).toBe('On its own');
    await log().trigger('click');
    expect(log().text()).toBe('Draft');
    await log().trigger('click');
    expect(log().text()).toBe('On its own');
  });

  it('depois do Marcador mostra o valor efetivo; desconto travado; gatilho pendente não liga', async () => {
    const wrapper = await montar();
    await clicar(wrapper, 'etapa-fase-negociacao');
    expect(achar(wrapper, 'limite-contrato_zapsign').text()).toContain(
      'limited by the marker'
    );
    expect(achar(wrapper, 'limite-desconto').text()).toContain(
      'Never · office rule'
    );
    expect(
      achar(wrapper, 'gatilho-irritado').attributes('disabled')
    ).toBeDefined();
    expect(achar(wrapper, 'gatilho-irritado').text()).toContain('text pending');

    await clicar(wrapper, 'gatilho-nao_le');
    expect(achar(wrapper, 'gatilho-nao_le').attributes('aria-pressed')).toBe(
      'true'
    );
    expect(achar(wrapper, 'selo').text()).toContain('1 adjustment');
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

  it('?alvo= abre o alvo pedido', async () => {
    useRoute().query = { alvo: 'tese:2' };
    const wrapper = await montar();
    expect(achar(wrapper, 'alvo-nome').text()).toBe('Auxílio-acidente');
    expect(achar(wrapper, 'selo').text()).toBe('Profile Fast');
  });
});
