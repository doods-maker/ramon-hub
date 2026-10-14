import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import RoteiroPassosAPI from 'dashboard/api/roteiroPassos';
import RoteiroEditor from '../RoteiroEditor.vue';

vi.mock('dashboard/api/roteiroPassos', () => ({
  default: {
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    reorder: vi.fn(),
  },
}));
const alertSpy = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...a) => alertSpy(...a),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const passo = (id, thesisId, position, chave, extra = {}) => ({
  id,
  thesis_id: thesisId,
  position,
  chave,
  titulo: chave.toUpperCase(),
  orientacao: '',
  tipo_resposta: 'sim_nao',
  opcoes: [],
  calculadora: null,
  calculadora_campos: {},
  saidas: [],
  ...extra,
});
const PASSOS = [
  passo(1, null, 0, 'tem_advogado'),
  passo(2, 5, 1, 'renda', {
    tipo_resposta: 'numero',
    saidas: [{ id: 's1', quando: '< 1000', acao: 'seguir' }],
  }),
  passo(3, 5, 0, 'recebeu'),
  passo(4, 9, 0, 'outra'),
];
const CALCULADORAS = {
  renda_per_capita: {
    campos: ['renda_total', 'moradores'],
    resultados: ['abaixo', 'acima', 'depende'],
  },
};

const store = createStore({
  modules: {
    leadConfig: {
      namespaced: true,
      getters: {
        getStages: () => [
          { id: 1, name: 'Qualificação', is_won: false, is_lost: false },
          { id: 2, name: 'Perdido', is_won: false, is_lost: true },
        ],
        getLostReasons: () => [{ id: 1, name: 'Sem viabilidade' }],
      },
    },
  },
});

const montar = thesisId =>
  mount(RoteiroEditor, {
    props: { thesisId, passos: PASSOS, calculadoras: CALCULADORAS },
    global: { plugins: [store], mocks: { $t: k => k } },
  });
const titulos = w =>
  w.findAll('[data-testid="roteiro-passo-abrir"]').map(b => b.text());

describe('RoteiroEditor', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('lista só os passos do escopo, na ordem', () => {
    expect(titulos(montar(5))).toEqual(['RECEBEU', 'RENDA']);
    expect(titulos(montar(null))).toEqual(['TEM_ADVOGADO']);
  });

  it('passo novo da tese: a chave sai do título e vai com o thesis_id', async () => {
    RoteiroPassosAPI.create.mockResolvedValue({ data: {} });
    const wrapper = montar(5);
    await wrapper.find('[data-testid="roteiro-novo"]').trigger('click');
    const titulo = wrapper.find('[data-testid="roteiro-titulo"]');
    await titulo.setValue('Qual a renda da casa?');
    await titulo.trigger('blur');
    expect(wrapper.find('[data-testid="roteiro-chave"]').element.value).toBe(
      'qual_a_renda_da_casa'
    );
    await wrapper.find('[data-testid="roteiro-salvar"]').trigger('click');
    await flushPromises();
    expect(RoteiroPassosAPI.create).toHaveBeenCalledWith(
      expect.objectContaining({
        titulo: 'Qual a renda da casa?',
        chave: 'qual_a_renda_da_casa',
        thesis_id: 5,
      })
    );
    expect(wrapper.emitted('mudou')).toHaveLength(1);
  });

  it('editar: chave travada; "vai para" lista comuns e os da tese, sem o próprio passo', async () => {
    const wrapper = montar(5);
    await wrapper
      .findAll('[data-testid="roteiro-passo-abrir"]')[0]
      .trigger('click');
    expect(
      wrapper.find('[data-testid="roteiro-chave"]').attributes()
    ).toHaveProperty('disabled');
    await wrapper.find('[data-testid="roteiro-nova-saida"]').trigger('click');
    await wrapper
      .find('[data-testid="roteiro-saida-acao"]')
      .setValue('ir_para');
    const alvos = wrapper
      .findAll('[data-testid="roteiro-saida-alvo"] option')
      .map(o => o.element.value);
    expect(alvos).toEqual(['', 'tem_advogado', 'renda']);
  });

  it('salvar manda só o que a ação usa', async () => {
    RoteiroPassosAPI.update.mockResolvedValue({ data: {} });
    const wrapper = montar(5);
    await wrapper
      .findAll('[data-testid="roteiro-passo-abrir"]')[0]
      .trigger('click');
    await wrapper.find('[data-testid="roteiro-nova-saida"]').trigger('click');
    await wrapper.find('[data-testid="roteiro-saida-quando"]').setValue('sim');
    await wrapper
      .find('[data-testid="roteiro-saida-acao"]')
      .setValue('desqualificar');
    await wrapper
      .find('[data-testid="roteiro-saida-motivo"]')
      .setValue('tem advogado');
    await wrapper.find('[data-testid="roteiro-salvar"]').trigger('click');
    await flushPromises();
    expect(RoteiroPassosAPI.update).toHaveBeenCalledWith(
      3,
      expect.objectContaining({
        saidas: [
          {
            id: 's1',
            quando: 'sim',
            acao: 'desqualificar',
            motivo: 'tem advogado',
          },
        ],
      })
    );
  });

  it('descer manda a ordem do escopo', async () => {
    RoteiroPassosAPI.reorder.mockResolvedValue({});
    const wrapper = montar(5);
    await wrapper
      .findAll('[data-testid="roteiro-passo-descer"]')[0]
      .trigger('click');
    await flushPromises();
    expect(RoteiroPassosAPI.reorder).toHaveBeenCalledWith([2, 3]);
  });

  it('remoção recusada mostra o motivo do servidor', async () => {
    RoteiroPassosAPI.delete.mockRejectedValue({
      response: { data: { error: 'Não dá para remover: RECEBEU aponta' } },
    });
    const wrapper = montar(5);
    await wrapper
      .findAll('[data-testid="roteiro-passo-remover"]')[1]
      .trigger('click');
    await wrapper
      .find('[data-testid="confirm-modal-confirm"]')
      .trigger('click');
    await flushPromises();
    expect(RoteiroPassosAPI.delete).toHaveBeenCalledWith(2);
    expect(alertSpy).toHaveBeenCalledWith(
      'Não dá para remover: RECEBEU aponta'
    );
  });
});
