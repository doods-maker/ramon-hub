import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ScenariosCard from '../ScenariosCard.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const montar = (tools, extra = {}) => {
  const store = createStore({
    modules: {
      teams: { namespaced: true, getters: { getTeams: () => [] } },
      captainTools: {
        namespaced: true,
        getters: {
          getRecords: () => [
            { id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao' },
          ],
        },
      },
    },
  });
  return mount(ScenariosCard, {
    props: {
      id: 1,
      title: 'Lead aceitou a reunião',
      description: 'Quando o lead topa conversar',
      instruction: 'Conduza a conversa',
      tools,
      ...extra,
    },
    global: {
      plugins: [store],
      stubs: {
        CardLayout: { template: '<div><slot /></div>' },
        Checkbox: true,
        Button: true,
        Icon: true,
        Editor: true,
        Input: true,
        TextArea: true,
      },
    },
  });
};

describe('ScenariosCard — ferramentas da skill', () => {
  it('mostra o nome legível com a cor do nível, e o id cru quando não está no catálogo', () => {
    const chips = montar(['mover_etapa', 'minha_http']).findAll(
      '[data-testid="skill-ferramenta"]'
    );
    expect(chips.map(chip => chip.text())).toEqual([
      'Mover de etapa',
      'minha_http',
    ]);
    expect(chips[0].classes()).toContain('text-n-amber-11');
    expect(chips[1].classes()).toContain('text-n-slate-11');
  });

  it('chave liga/desliga emite toggle com o novo estado', async () => {
    const wrapper = montar([], { enabled: true, podeLigar: true });
    await wrapper.find('[data-testid="skill-chave"]').trigger('click');
    expect(wrapper.emitted('toggle')[0]).toEqual([false]);
  });

  it('sem permissão não mostra a chave; editada mostra a marca', () => {
    const wrapper = montar([], { edited: true });
    expect(wrapper.find('[data-testid="skill-chave"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="skill-editada"]').text()).toBe(
      'INTEL.SKILLS.EDITADA'
    );
  });

  it('skill sem ferramentas (tools null da API) não mostra a linha', () => {
    expect(montar(null).text()).not.toContain(
      'CAPTAIN.ASSISTANTS.SCENARIOS.ADD.SUGGESTED.TOOLS_USED'
    );
  });
});

describe('ScenariosCard — A5', () => {
  it('"Testar esta skill" só com fala de exemplo e emite testar', async () => {
    expect(montar([]).find('[data-testid="skill-testar"]').exists()).toBe(
      false
    );
    const wrapper = montar([], { exemplo: 'Como está o funil hoje?' });
    await wrapper.find('[data-testid="skill-testar"]').trigger('click');
    expect(wrapper.emitted('testar')).toHaveLength(1);
  });

  it('mostra o uso de 30 dias e os papéis', () => {
    const wrapper = montar([], { usoMes: 4, papeis: ['comercial'] });
    expect(wrapper.find('[data-testid="skill-uso"]').text()).toBe(
      'INTEL.SKILLS.USO_30D'
    );
    expect(
      wrapper.findAll('[data-testid="skill-papel"]').map(c => c.text())
    ).toEqual(['comercial']);
    expect(
      montar([], { usoMes: 0 }).find('[data-testid="skill-uso"]').text()
    ).toBe('INTEL.SKILLS.SEM_USO_30D');
  });
});
