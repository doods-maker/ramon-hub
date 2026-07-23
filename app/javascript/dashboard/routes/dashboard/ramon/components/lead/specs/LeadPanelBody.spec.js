import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadPanelBody from '../LeadPanelBody.vue';
import LostReasonModal from '../../kanban/LostReasonModal.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const lead = {
  id: 7,
  name: 'Maria de Lourdes',
  lead_stage_id: 1,
  conversation_id: 42,
  value: 48000,
  benefit_type_name: 'B31 · Auxílio-doença',
  thesis_name: 'Restabelecimento B31',
  sdr_name: 'Eduardo',
  closer_name: 'Camila',
  contact_phone: '+55489999',
  contact_cpf: '05231877490',
  lost_reason: null,
};

const build = ({
  update = vi.fn(),
  del = vi.fn(),
  createTask = vi.fn(),
} = {}) =>
  createStore({
    modules: {
      leads: {
        namespaced: true,
        actions: { update, delete: del },
      },
      leadConfig: {
        namespaced: true,
        getters: {
          getStages: () => [
            { id: 1, name: 'Novo' },
            { id: 2, name: 'Fechado', is_won: true },
            { id: 3, name: 'Perdido', is_lost: true },
          ],
          getLostReasons: () => [],
        },
      },
      leadTasks: {
        namespaced: true,
        getters: { getByLead: () => () => [] },
        actions: { fetchForLead: vi.fn(), create: createTask },
      },
    },
  });

const stubs = {
  LeadNextAction: true,
  LeadZapsignCard: true,
  LeadCopilot: true,
  LeadFields: true,
  LeadHistory: true,
  LeadPlaybook: true,
  LeadTriage: true,
  LeadKit: true,
  LeadSimulador: true,
  ConversationAction: true,
  MacrosList: true,
  ResolveAction: true,
  RouterLink: { template: '<a><slot /></a>' },
};

const mountBody = ({ props = {}, spies = {} } = {}) =>
  shallowMount(LeadPanelBody, {
    props: { lead, context: 'conversation', conversationId: 42, ...props },
    global: {
      plugins: [build(spies)],
      mocks: { $t: k => k },
      stubs,
    },
  });

describe('LeadPanelBody', () => {
  beforeEach(() => {
    localStorage.clear();
    Element.prototype.scrollIntoView = vi.fn();
  });

  describe('abas', () => {
    it('abre no Resumo por padrão com o card de próxima ação', () => {
      const wrapper = mountBody();
      expect(wrapper.findComponent({ name: 'LeadNextAction' }).exists()).toBe(
        true
      );
      expect(wrapper.findComponent({ name: 'LeadHistory' }).exists()).toBe(
        false
      );
    });

    it('troca o conteúdo ao clicar em outra aba e persiste a escolha', async () => {
      const wrapper = mountBody();
      await wrapper.find('[data-testid="lead-tab-historico"]').trigger('click');
      expect(wrapper.findComponent({ name: 'LeadHistory' }).exists()).toBe(
        true
      );
      // Próxima ação vive no cabeçalho: continua visível em qualquer aba
      expect(wrapper.findComponent({ name: 'LeadNextAction' }).exists()).toBe(
        true
      );
      expect(localStorage.getItem('ramon_lead_panel_tab')).toBe('historico');
    });

    it('só mostra a aba Contrato pra tese elegível (acidente)', () => {
      expect(
        mountBody().find('[data-testid="lead-tab-contrato"]').exists()
      ).toBe(false);
      const wrapper = mountBody({
        props: { lead: { ...lead, thesis_name: 'Auxílio-acidente' } },
      });
      expect(wrapper.find('[data-testid="lead-tab-contrato"]').exists()).toBe(
        true
      );
    });

    it('aba Contrato persistida cai no Resumo quando o lead não é elegível', () => {
      localStorage.setItem('ramon_lead_panel_tab', 'contrato');
      const wrapper = mountBody();
      expect(wrapper.findComponent({ name: 'LeadCopilot' }).exists()).toBe(
        true
      );
      expect(wrapper.findComponent({ name: 'LeadZapsignCard' }).exists()).toBe(
        false
      );
    });

    it('agrupa Triagem + Kit na aba IA', async () => {
      const wrapper = mountBody();
      await wrapper.find('[data-testid="lead-tab-ia"]').trigger('click');
      expect(wrapper.findComponent({ name: 'LeadTriage' }).exists()).toBe(true);
      expect(wrapper.findComponent({ name: 'LeadKit' }).exists()).toBe(true);
      expect(wrapper.findComponent({ name: 'LeadCopilot' }).exists()).toBe(
        true
      );
    });

    it('restaura a aba persistida', () => {
      localStorage.setItem('ramon_lead_panel_tab', 'simulador');
      const wrapper = mountBody();
      expect(wrapper.findComponent({ name: 'LeadSimulador' }).exists()).toBe(
        true
      );
    });

    it('mostra dot âmbar na IA quando a triagem aguarda humano', () => {
      const wrapper = mountBody({
        props: {
          lead: { ...lead, latest_triage: { status: 'awaiting_human' } },
        },
      });
      const dot = wrapper.find('[data-testid="lead-tab-dot-ia"]');
      expect(dot.exists()).toBe(true);
      expect(dot.classes()).toContain('bg-n-amber-9');
    });

    it('mostra dot verde no Simulador quando há última simulação', () => {
      const wrapper = mountBody({
        props: {
          lead: { ...lead, custom_attributes: { ultima_simulacao: { x: 1 } } },
        },
      });
      const dot = wrapper.find('[data-testid="lead-tab-dot-simulador"]');
      expect(dot.exists()).toBe(true);
      expect(dot.classes()).toContain('bg-n-teal-9');
    });
  });

  describe('chip de etapa com guarda', () => {
    it('abre o LostReasonModal em etapa de perda sem motivo, sem PATCH', async () => {
      const update = vi.fn();
      const wrapper = mountBody({ spies: { update } });
      await wrapper.find('[data-testid="panel-stage"]').setValue(3);
      expect(update).not.toHaveBeenCalled();
      expect(wrapper.findComponent(LostReasonModal).exists()).toBe(true);
    });

    it('faz o PATCH com lost_reason quando o modal confirma', async () => {
      const update = vi.fn();
      const wrapper = mountBody({ spies: { update } });
      await wrapper.find('[data-testid="panel-stage"]').setValue(3);
      wrapper
        .findComponent(LostReasonModal)
        .vm.$emit('confirmMove', { lostReason: 'Sem retorno' });
      await flushPromises();
      expect(update).toHaveBeenCalledWith(expect.anything(), {
        id: 7,
        lead_stage_id: 3,
        lost_reason: 'Sem retorno',
      });
    });

    it('pede o valor em etapa de ganho quando o lead não tem valor', async () => {
      const update = vi.fn();
      const wrapper = mountBody({
        props: { lead: { ...lead, value: null } },
        spies: { update },
      });
      await wrapper.find('[data-testid="panel-stage"]').setValue(2);
      expect(update).not.toHaveBeenCalled();
      expect(wrapper.find('[data-testid="stage-won-prompt"]').exists()).toBe(
        true
      );
      await wrapper
        .find('[data-testid="stage-won-value"]')
        .setValue('2.500,00');
      await wrapper.find('[data-testid="stage-won-save"]').trigger('click');
      expect(update).toHaveBeenCalledWith(expect.anything(), {
        id: 7,
        lead_stage_id: 2,
        value: 2500,
      });
    });

    it('troca direto quando não há guarda a acionar', async () => {
      const update = vi.fn();
      const wrapper = mountBody({ spies: { update } });
      await wrapper.find('[data-testid="panel-stage"]').setValue(2);
      expect(update).toHaveBeenCalledWith(expect.anything(), {
        id: 7,
        lead_stage_id: 2,
      });
    });
  });

  describe('ações do cabeçalho', () => {
    it('no drawer, WhatsApp emite openConversation', async () => {
      const wrapper = mountBody({ props: { context: 'drawer' } });
      await wrapper.find('[data-testid="panel-whatsapp"]').trigger('click');
      expect(wrapper.emitted('openConversation')[0]).toEqual([42]);
    });

    it('na conversa não mostra WhatsApp (a conversa já está aberta) e mostra Resolver', () => {
      const wrapper = mountBody();
      expect(wrapper.find('[data-testid="panel-whatsapp"]').exists()).toBe(
        false
      );
      expect(wrapper.findComponent({ name: 'ResolveAction' }).exists()).toBe(
        true
      );
    });

    it('sem conversa, WhatsApp vira link wa.me', () => {
      const wrapper = mountBody({
        props: { lead: { ...lead, conversation_id: null } },
      });
      const link = wrapper.find('[data-testid="panel-whatsapp-wa-me"]');
      expect(link.exists()).toBe(true);
      expect(link.attributes('href')).toContain('wa.me');
    });

    it('cria tarefa pelo form inline com guard de duplo-clique', async () => {
      // promise pendurada: o form segue aberto e o 2º clique cai no guard
      const createTask = vi.fn(() => new Promise(() => {}));
      const wrapper = mountBody({ spies: { createTask } });
      await wrapper.find('[data-testid="panel-add-task"]').trigger('click');
      await wrapper.find('[data-testid="panel-task-title"]').setValue('Ligar');
      await wrapper.find('[data-testid="panel-task-save"]').trigger('click');
      await wrapper.find('[data-testid="panel-task-save"]').trigger('click');
      expect(createTask).toHaveBeenCalledTimes(1);
      expect(createTask).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ leadId: 7, title: 'Ligar' })
      );
    });
  });

  describe('resumo', () => {
    it('mostra o grid read-only com os dados do lead', () => {
      const wrapper = mountBody();
      expect(wrapper.text()).toContain('Restabelecimento B31');
      expect(wrapper.text()).toContain('Eduardo / Camila');
      expect(wrapper.text()).toContain('052.318.774-90');
    });

    it('expande o formulário completo pelo link "editar todos os campos"', async () => {
      const wrapper = mountBody();
      expect(wrapper.findComponent({ name: 'LeadFields' }).exists()).toBe(
        false
      );
      await wrapper
        .find('[data-testid="lead-edit-all-toggle"]')
        .trigger('click');
      expect(wrapper.findComponent({ name: 'LeadFields' }).exists()).toBe(true);
    });

    it('completeData do ZapSign (aba Contrato) volta pro Resumo com o formulário aberto', async () => {
      const wrapper = mountBody({
        props: { lead: { ...lead, thesis_name: 'Auxílio-acidente' } },
      });
      await wrapper.find('[data-testid="lead-tab-contrato"]').trigger('click');
      wrapper
        .findComponent({ name: 'LeadZapsignCard' })
        .vm.$emit('completeData');
      await flushPromises();
      expect(wrapper.find('[data-testid="lead-all-fields"]').exists()).toBe(
        true
      );
    });

    it('descarta o lead só após confirmação inline', async () => {
      const del = vi.fn();
      const wrapper = mountBody({ spies: { del } });
      await wrapper.find('[data-testid="lead-discard"]').trigger('click');
      expect(del).not.toHaveBeenCalled();
      await wrapper
        .find('[data-testid="lead-discard-confirm"]')
        .trigger('click');
      await flushPromises();
      expect(del).toHaveBeenCalledWith(expect.anything(), 7);
      expect(wrapper.emitted('discarded')).toBeTruthy();
    });

    it('no drawer não há "Não é lead" nem ações nativas da conversa', () => {
      const wrapper = mountBody({ props: { context: 'drawer' } });
      expect(wrapper.find('[data-testid="lead-discard"]').exists()).toBe(false);
      expect(
        wrapper.findComponent({ name: 'ConversationAction' }).exists()
      ).toBe(false);
    });
  });
});
