import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadApto from '../LeadApto.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const aguardando = {
  id: 7,
  closer_id: 5,
  apto_situacao: 'aguardando',
  apto_prazo: '2026-11-23T13:00:00Z',
  apto_pode_validar: true,
  validador_id: null,
};

const build = ({ apto = vi.fn(), role = 'agent', userId = 1 } = {}) =>
  createStore({
    getters: {
      getCurrentRole: () => role,
      getCurrentUserID: () => userId,
    },
    modules: {
      leads: { namespaced: true, actions: { apto } },
      agents: {
        namespaced: true,
        getters: { getAgents: () => [{ id: 9, name: 'Dra. Crisleine' }] },
      },
    },
  });

const montar = (lead, storeOpts = {}) =>
  mount(LeadApto, {
    props: { lead },
    global: { plugins: [build(storeOpts)], mocks: { $t: k => k } },
  });

const botao = (wrapper, id) => wrapper.find(`[data-testid="${id}"]`);

describe('LeadApto', () => {
  it('advogada da tese vê validar e devolver; validar chama a ação', async () => {
    const apto = vi.fn();
    const wrapper = montar(aguardando, { apto });

    expect(botao(wrapper, 'apto-devolver').exists()).toBe(true);
    await botao(wrapper, 'apto-validar').trigger('click');

    expect(apto).toHaveBeenCalledWith(expect.anything(), {
      id: 7,
      acao: 'validar',
    });
  });

  it('quem não pode validar só vê a situação', () => {
    const wrapper = montar({ ...aguardando, apto_pode_validar: false });

    expect(botao(wrapper, 'apto-validar').exists()).toBe(false);
    expect(botao(wrapper, 'apto-devolver').exists()).toBe(false);
    expect(wrapper.text()).toContain('RAMON.APTO.SITUACAO.aguardando');
  });

  it('sem assinatura conferida no ZapSign avisa que não fica apto por prazo', () => {
    const aviso = lead =>
      botao(montar(lead), 'apto-sem-assinatura').exists() &&
      botao(montar(lead), 'apto-sem-assinatura').text();

    expect(
      aviso({ ...aguardando, apto_prazo: null, assinatura_conferida: false })
    ).toBe('RAMON.APTO.SEM_ASSINATURA');
    expect(aviso({ ...aguardando, assinatura_conferida: true })).toBe(false);
    // só enquanto aguarda: validado na mão (contrato em papel) não avisa mais
    expect(
      aviso({
        ...aguardando,
        apto_situacao: 'apto',
        assinatura_conferida: false,
      })
    ).toBe(false);
  });

  it('devolver exige motivo antes de enviar', async () => {
    const apto = vi.fn();
    const wrapper = montar(aguardando, { apto });

    await botao(wrapper, 'apto-devolver').trigger('click');
    expect(
      botao(wrapper, 'apto-devolver-confirmar').attributes()
    ).toHaveProperty('disabled');

    await wrapper.find('[data-testid="apto-motivo"]').setValue('Falta o laudo');
    await botao(wrapper, 'apto-devolver-confirmar').trigger('click');
    await flushPromises();

    expect(apto).toHaveBeenCalledWith(expect.anything(), {
      id: 7,
      acao: 'devolver',
      motivo: 'Falta o laudo',
    });
  });

  it('devolvido: mostra o motivo e o Closer do lead reenvia', async () => {
    const apto = vi.fn();
    const devolvido = {
      ...aguardando,
      apto_situacao: 'devolvido',
      apto_pode_validar: false,
      devolvido_motivo: 'Falta o laudo',
    };
    const wrapper = montar(devolvido, { apto, userId: 5 });

    expect(wrapper.text()).toContain('Falta o laudo');
    await botao(wrapper, 'apto-reenviar').trigger('click');

    expect(apto).toHaveBeenCalledWith(expect.anything(), {
      id: 7,
      acao: 'reenviar',
    });
  });

  it('só o admin designa o advogado do lead', async () => {
    const apto = vi.fn();
    expect(
      montar(aguardando).find('[data-testid="apto-designar"]').exists()
    ).toBe(false);

    const wrapper = montar(aguardando, { apto, role: 'administrator' });
    await wrapper.find('[data-testid="apto-designar"]').setValue('9');

    expect(apto).toHaveBeenCalledWith(expect.anything(), {
      id: 7,
      acao: 'designar',
      userId: 9,
    });
  });
});
