import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import PainelPasso from '../PainelPasso.vue';

const store = createStore({
  modules: {
    leadConfig: {
      namespaced: true,
      getters: {
        getStages: () => [{ id: 3, name: 'Contrato assinado' }],
        getPriorities: () => [],
      },
    },
    agents: {
      namespaced: true,
      getters: { getAgents: () => [{ id: 1, name: 'Ana' }] },
    },
    inboxes: {
      namespaced: true,
      getters: { getInboxes: () => [{ id: 7, name: 'WhatsApp' }] },
    },
    labels: {
      namespaced: true,
      getters: { getLabels: () => [{ id: 1, title: 'urgente' }] },
    },
    teams: {
      namespaced: true,
      getters: { getTeams: () => [{ id: 2, name: 'Comercial' }] },
    },
    theses: {
      namespaced: true,
      getters: { getTheses: () => [{ id: 1, name: 'BPC' }] },
    },
  },
});
const montar = no =>
  mount(PainelPasso, {
    props: { no, erros: [] },
    global: { plugins: [store] },
  });

describe('PainelPasso', () => {
  it('rascunho: avisa que sai como rascunho e edita o texto', async () => {
    const wrapper = montar({
      id: 'n2',
      data: { tipo: 'rascunho_texto', config: { texto: 'Oi' } },
    });
    expect(wrapper.find('[data-testid="painel-aviso-rascunho"]').exists()).toBe(
      true
    );
    await wrapper.find('textarea').setValue('Olá');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([{ texto: 'Olá' }]);
  });

  it('clicar numa variável insere {chave} no cursor', async () => {
    const wrapper = montar({
      id: 'n2',
      data: { tipo: 'nota_privada', config: { texto: 'Oi ' } },
    });
    const area = wrapper.find('textarea').element;
    area.setSelectionRange(3, 3);
    await wrapper.find('[data-testid="var-nome"]').trigger('click');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { texto: 'Oi {nome}' },
    ]);
  });

  it('mover etapa usa as etapas do funil', async () => {
    const wrapper = montar({
      id: 'n3',
      data: { tipo: 'mover_etapa', config: {} },
    });
    await wrapper.find('select').setValue('3');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([{ etapa_id: 3 }]);
  });

  it('gatilho não tem Duplicar/Excluir', () => {
    const wrapper = montar({
      id: 'n1',
      data: { tipo: 'gatilho', config: { tipo: 'manual' } },
    });
    expect(wrapper.find('[data-testid="painel-excluir"]').exists()).toBe(false);
  });

  it('erros do passo aparecem no topo', () => {
    const wrapper = mount(PainelPasso, {
      props: {
        no: { id: 'n2', data: { tipo: 'nota_privada', config: {} } },
        erros: ['Falta preencher o texto.'],
      },
      global: { plugins: [store] },
    });
    expect(wrapper.text()).toContain('Falta preencher o texto.');
  });

  it('webhook: só o endereço', async () => {
    const wrapper = montar({ id: 'n9', data: { tipo: 'webhook', config: {} } });
    await wrapper
      .find('[data-testid="webhook-url"]')
      .setValue('https://hooks.exemplo.com.br/a');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { url: 'https://hooks.exemplo.com.br/a' },
    ]);
  });

  it('trocar responsável: papel + pessoa (vazio = distribuir no time)', async () => {
    const wrapper = montar({
      id: 'n4',
      data: { tipo: 'trocar_responsavel', config: { papel: 'closer' } },
    });
    await wrapper.find('[data-testid="papel"]').setValue('sdr');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([{ papel: 'sdr' }]);
  });

  it('preencher campo: chave e valor', async () => {
    const wrapper = montar({
      id: 'n5',
      data: { tipo: 'preencher_campo', config: {} },
    });
    await wrapper.find('[data-testid="campo-chave"]').setValue('beneficio');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { chave: 'beneficio' },
    ]);
  });

  it('rascunho da IA mostra o aviso de rascunho', () => {
    const wrapper = montar({
      id: 'n6',
      data: { tipo: 'rascunho_ia', config: {} },
    });
    expect(wrapper.find('[data-testid="painel-aviso-rascunho"]').exists()).toBe(
      true
    );
  });

  it('gatilho relógio: hora', async () => {
    const wrapper = montar({
      id: 'n1',
      data: { tipo: 'gatilho', config: { tipo: 'relogio' } },
    });
    await wrapper.find('[data-testid="gatilho-hora"]').setValue('09:30');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { tipo: 'relogio', hora: '09:30' },
    ]);
  });

  it('gatilho evento do ADVBOX: marca as regras', async () => {
    const wrapper = montar({
      id: 'n1',
      data: { tipo: 'gatilho', config: { tipo: 'evento_advbox' } },
    });
    await wrapper.find('input[type="checkbox"]').setValue(true);
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { tipo: 'evento_advbox', regras: ['contrato_fechado'] },
    ]);
  });
});
