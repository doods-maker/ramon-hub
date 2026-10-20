import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import AtendimentosHoje from '../AtendimentosHoje.vue';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import ChegadasAPI from 'dashboard/api/ramonChegadas';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
const alertSpy = vi.fn();
vi.mock('dashboard/composables', () => ({ useAlert: m => alertSpy(m) }));
vi.mock('dashboard/api/ramonChegadas', () => ({
  default: { agenda: vi.fn(), create: vi.fn(), get: vi.fn() },
}));

const comAdvogado = {
  advbox_post_id: 5,
  cliente_nome: 'JOÃO PEREIRA',
  advbox_customer_id: 7,
  responsavel_advbox: 'TAMIRES DE FARIAS',
  destinatario_id: 30,
};
const semAdvogado = {
  advbox_post_id: 6,
  cliente_nome: 'ANA LIMA',
  advbox_customer_id: 8,
  responsavel_advbox: 'FULANO SEM HUB',
  destinatario_id: null,
};

const montar = async (agenda = [comAdvogado, semAdvogado], chegadas = []) => {
  ChegadasAPI.agenda.mockResolvedValue({ data: { payload: agenda } });
  ChegadasAPI.get.mockResolvedValue({
    data: { payload: chegadas, pode_avisar: true },
  });
  const wrapper = mount(AtendimentosHoje);
  await flushPromises();
  return wrapper;
};

const linha = (wrapper, nome) =>
  wrapper
    .findAll('[data-testid="atendimento"]')
    .find(l => l.text().includes(nome));

describe('AtendimentosHoje.vue', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  it('lista os atendimentos do ADVBOX com o botão Chegou', async () => {
    const wrapper = await montar();
    expect(wrapper.findAll('[data-testid="atendimento"]')).toHaveLength(2);
    expect(
      linha(wrapper, 'JOÃO').find('[data-testid="atendimento-chegou"]').exists()
    ).toBe(true);
  });

  it('Chegou avisa direto o advogado casado, com motivo Reunião', async () => {
    ChegadasAPI.create.mockResolvedValue({
      data: {
        id: 1,
        cliente_nome: 'JOÃO PEREIRA',
        estado: 'aguardando',
        criado_por: { id: 1 },
        destinatario: { id: 30 },
      },
    });
    const wrapper = await montar();
    await linha(wrapper, 'JOÃO')
      .find('[data-testid="atendimento-chegou"]')
      .trigger('click');
    await flushPromises();

    expect(ChegadasAPI.create).toHaveBeenCalledWith({
      cliente_nome: 'JOÃO PEREIRA',
      advbox_customer_id: 7,
      advbox_post_id: 5,
      motivo: 'RAMON.CHEGADA.MOTIVO_REUNIAO',
      destinatario_id: 30,
    });
    expect(
      linha(wrapper, 'JOÃO').find('[data-testid="atendimento-estado"]').text()
    ).toBe('RAMON.CHEGADA.ESTADO_aguardando');
  });

  it('sem advogado casado, Chegou abre o painel com o nome', async () => {
    const wrapper = await montar();
    const store = useChegadasStore();
    await linha(wrapper, 'ANA')
      .find('[data-testid="atendimento-chegou"]')
      .trigger('click');
    expect(ChegadasAPI.create).not.toHaveBeenCalled();
    expect(store.painelPedido).toBe(1);
    expect(store.painelPrefill).toEqual(semAdvogado);
  });

  it('"Chegou alguém sem horário" abre o painel vazio', async () => {
    const wrapper = await montar();
    const store = useChegadasStore();
    await wrapper.find('[data-testid="chegou-sem-horario"]').trigger('click');
    expect(store.painelPedido).toBe(1);
    expect(store.painelPrefill).toBeNull();
  });

  it('quem já chegou mostra o estado no lugar do botão', async () => {
    const wrapper = await montar(
      [comAdvogado],
      [
        {
          id: 9,
          cliente_nome: 'JOÃO PEREIRA',
          estado: 'respondido',
          criado_por: { id: 1 },
          destinatario: { id: 30 },
        },
      ]
    );
    expect(wrapper.find('[data-testid="atendimento-chegou"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="atendimento-estado"]').text()).toBe(
      'RAMON.CHEGADA.ESTADO_respondido'
    );
  });

  it('falha ao avisar mostra alerta', async () => {
    ChegadasAPI.create.mockRejectedValue(new Error('422'));
    const wrapper = await montar();
    await linha(wrapper, 'JOÃO')
      .find('[data-testid="atendimento-chegou"]')
      .trigger('click');
    await flushPromises();
    expect(alertSpy).toHaveBeenCalledWith('RAMON.CHEGADA.ERRO_AVISAR');
  });
});
