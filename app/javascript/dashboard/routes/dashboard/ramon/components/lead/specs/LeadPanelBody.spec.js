import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadPanelBody from '../LeadPanelBody.vue';
import LostReasonModal from '../../kanban/LostReasonModal.vue';
import LeadReuniao from '../LeadReuniao.vue';
import { formatBrl } from '../../../helpers/currency';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({ copyTextToClipboard: vi.fn() }));

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
  followUpDraft = vi.fn(),
  agendarReuniao = vi.fn(),
  tasks = [],
  chatMessages = [],
} = {}) =>
  createStore({
    getters: { getSelectedChat: () => ({ id: 42, messages: chatMessages }) },
    modules: {
      leads: {
        namespaced: true,
        actions: { update, delete: del, followUpDraft, agendarReuniao },
      },
      leadConfig: {
        namespaced: true,
        getters: {
          getStages: () => [
            { id: 1, name: 'Novo', probability: 10 },
            { id: 2, name: 'Fechado', is_won: true },
            { id: 3, name: 'Perdido', is_lost: true },
            { id: 4, name: 'Reunião', label: 'fase-reuniao-agendada' },
          ],
          getLostReasons: () => [],
          getBenefitTypes: () => [{ id: 31, name: 'B31' }],
          getChannels: () => [{ key: 'whatsapp', label: 'WhatsApp' }],
        },
      },
      theses: {
        namespaced: true,
        getters: {
          getTheses: () => [
            { id: 5, name: 'Restabelecimento B31', active: true },
            { id: 6, name: 'Antiga', active: false },
          ],
        },
      },
      leadTasks: {
        namespaced: true,
        getters: { getByLead: () => () => tasks },
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
  LeadSimulador: true,
  ConversationAction: true,
  MacrosList: true,
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
      // Próxima ação agora vive no corpo do Resumo (cartões enxutos, D3):
      // some ao trocar de aba.
      expect(wrapper.findComponent({ name: 'LeadNextAction' }).exists()).toBe(
        false
      );
      expect(localStorage.getItem('ramon_lead_panel_tab')).toBe('historico');
    });

    it('mostra a aba Contrato em qualquer tese', () => {
      expect(
        mountBody().find('[data-testid="lead-tab-contrato"]').exists()
      ).toBe(true);
      const wrapper = mountBody({
        props: { lead: { ...lead, thesis_name: 'Auxílio-acidente' } },
      });
      expect(wrapper.find('[data-testid="lead-tab-contrato"]').exists()).toBe(
        true
      );
    });

    it('aba Contrato persistida abre o cartão do ZapSign', () => {
      localStorage.setItem('ramon_lead_panel_tab', 'contrato');
      const wrapper = mountBody();
      expect(wrapper.findComponent({ name: 'LeadCopilot' }).exists()).toBe(
        false
      );
      expect(wrapper.findComponent({ name: 'LeadZapsignCard' }).exists()).toBe(
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

  describe('badge de valor estimado automático no chip', () => {
    it('mostra o badge quando origem é auto', () => {
      const wrapper = mountBody({
        props: {
          lead: {
            ...lead,
            custom_attributes: { valor_estimado: { origem: 'auto' } },
          },
        },
      });
      expect(wrapper.find('[data-testid="value-auto-badge"]').exists()).toBe(
        true
      );
    });

    it('esconde o badge quando origem é manual', () => {
      const wrapper = mountBody({
        props: {
          lead: {
            ...lead,
            custom_attributes: { valor_estimado: { origem: 'manual' } },
          },
        },
      });
      expect(wrapper.find('[data-testid="value-auto-badge"]').exists()).toBe(
        false
      );
    });

    it('esconde o badge quando não há flag', () => {
      const wrapper = mountBody();
      expect(wrapper.find('[data-testid="value-auto-badge"]').exists()).toBe(
        false
      );
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

    it('pede confirmação pré-preenchida quando o lead já tem valor (ganho nunca é silencioso)', async () => {
      const update = vi.fn();
      const wrapper = mountBody({ spies: { update } }); // lead.value = 48000
      await wrapper.find('[data-testid="panel-stage"]').setValue(2);
      expect(update).not.toHaveBeenCalled();
      expect(wrapper.find('[data-testid="stage-won-prompt"]').exists()).toBe(
        true
      );
      expect(
        wrapper.find('[data-testid="stage-won-value"]').element.value
      ).toBe(formatBrl(48000));

      await wrapper.find('[data-testid="stage-won-save"]').trigger('click');
      expect(update).toHaveBeenCalledWith(expect.anything(), {
        id: 7,
        lead_stage_id: 2,
        value: 48000,
      });
    });
  });

  describe('ações do cabeçalho', () => {
    it('no drawer, WhatsApp emite openConversation', async () => {
      const wrapper = mountBody({ props: { context: 'drawer' } });
      await wrapper.find('[data-testid="panel-whatsapp"]').trigger('click');
      expect(wrapper.emitted('openConversation')[0]).toEqual([42]);
    });

    it('na conversa não mostra WhatsApp nem Resolver (já estão no cabeçalho da conversa)', () => {
      const wrapper = mountBody();
      expect(wrapper.find('[data-testid="panel-whatsapp"]').exists()).toBe(
        false
      );
      expect(wrapper.findComponent({ name: 'ResolveAction' }).exists()).toBe(
        false
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

  describe('valor editável no chip do cabeçalho', () => {
    const editar = async (wrapper, texto) => {
      await wrapper.find('[data-testid="panel-value-chip"]').trigger('click');
      const input = wrapper.find('[data-testid="field-value"]');
      await input.setValue(texto);
      return input;
    };

    it('clicar no chip abre o input já com o valor; Enter salva o número', async () => {
      const update = vi.fn();
      const wrapper = mountBody({ spies: { update } });
      await wrapper.find('[data-testid="panel-value-chip"]').trigger('click');
      const input = wrapper.find('[data-testid="field-value"]');
      expect(input.element.value).toBe(formatBrl(48000));
      await input.setValue('1.234,56');
      await input.trigger('keyup.enter');
      expect(update).toHaveBeenCalledWith(expect.anything(), {
        id: 7,
        value: 1234.56,
      });
      expect(wrapper.find('[data-testid="field-value"]').exists()).toBe(false);
    });

    it('texto inválido ou Esc não salvam', async () => {
      const update = vi.fn();
      const wrapper = mountBody({ spies: { update } });
      await (await editar(wrapper, 'abc')).trigger('blur');
      const input = await editar(wrapper, '999');
      await input.trigger('keyup.esc');
      expect(update).not.toHaveBeenCalled();
    });

    it('lead sem valor mostra "+ valor" no chip', () => {
      const wrapper = mountBody({ props: { lead: { ...lead, value: null } } });
      expect(wrapper.find('[data-testid="panel-value-chip"]').text()).toBe(
        'RAMON.LEAD_PANEL.VALUE_ADD'
      );
    });
  });

  describe('cartão Caso editável no lugar', () => {
    it('tese, benefício e canal salvam no change', async () => {
      const update = vi.fn();
      const wrapper = mountBody({ spies: { update } });
      await wrapper.find('[data-testid="field-thesis"]').setValue('5');
      await wrapper.find('[data-testid="field-benefit"]').setValue('31');
      await wrapper.find('[data-testid="field-channel"]').setValue('whatsapp');
      expect(update).toHaveBeenCalledWith(expect.anything(), {
        id: 7,
        thesis_id: 5,
      });
      expect(update).toHaveBeenCalledWith(expect.anything(), {
        id: 7,
        benefit_type_id: 31,
      });
      expect(update).toHaveBeenCalledWith(expect.anything(), {
        id: 7,
        channel: 'whatsapp',
      });
    });

    it('DCB salva no change e vazio limpa', async () => {
      const update = vi.fn();
      const wrapper = mountBody({ spies: { update } });
      const dcb = wrapper.find('[data-testid="field-dcb-em"]');
      await dcb.setValue('2021-12-10');
      await dcb.setValue('');
      expect(update).toHaveBeenCalledWith(expect.anything(), {
        id: 7,
        dcb_em: '2021-12-10',
      });
      expect(update).toHaveBeenCalledWith(expect.anything(), {
        id: 7,
        dcb_em: null,
      });
    });

    it('sem tese mostra o hint; tese inativa continua aparecendo', () => {
      expect(mountBody().find('[data-testid="no-thesis-hint"]').exists()).toBe(
        true
      );
      const wrapper = mountBody({
        props: { lead: { ...lead, thesis_id: 6, thesis_name: 'Antiga' } },
      });
      expect(wrapper.find('[data-testid="no-thesis-hint"]').exists()).toBe(
        false
      );
      const tese = wrapper.find('[data-testid="field-thesis"]');
      expect(tese.element.value).toBe('6');
      expect(tese.text()).toContain('Antiga');
    });
  });

  describe('+ Tarefa → Reunião', () => {
    const abrirReuniao = async wrapper => {
      await wrapper.find('[data-testid="panel-add-task"]').trigger('click');
      await wrapper
        .find('[data-testid="panel-task-kind-meeting"]')
        .trigger('click');
    };

    it('exige data/hora: sem ela não marca nada', async () => {
      const agendarReuniao = vi.fn();
      const wrapper = mountBody({ spies: { agendarReuniao } });
      await abrirReuniao(wrapper);
      const salvar = wrapper.find('[data-testid="panel-task-save"]');
      expect(salvar.attributes('disabled')).toBeDefined();
      expect(agendarReuniao).not.toHaveBeenCalled();
    });

    it('marca pela action de reunião (não cria follow-up), avisa e recarrega as notas', async () => {
      useAlert.mockClear();
      const agendarReuniao = vi.fn();
      const createTask = vi.fn();
      const wrapper = mountBody({ spies: { agendarReuniao, createTask } });
      await abrirReuniao(wrapper);
      await wrapper
        .find('[data-testid="panel-task-title"]')
        .setValue('Reunião');
      await wrapper
        .find('[data-testid="panel-task-date"]')
        .setValue('2026-10-06T14:00');
      await wrapper.find('[data-testid="panel-task-save"]').trigger('click');
      await flushPromises();
      expect(createTask).not.toHaveBeenCalled();
      expect(agendarReuniao).toHaveBeenCalledWith(expect.anything(), {
        id: 7,
        startsAt: new Date('2026-10-06T14:00').toISOString(),
        title: 'Reunião',
      });
      expect(useAlert).toHaveBeenCalledWith('RAMON.TASKS.MEETING_SCHEDULED');
      expect(
        wrapper.findComponent({ name: 'LeadNotes' }).props('refreshKey')
      ).toBe('undefined-1');
      expect(wrapper.find('[data-testid="panel-task-form"]').exists()).toBe(
        false
      );
    });
  });

  describe('Reunião (Closer) no Andamento', () => {
    const reuniaoVisivel = opts =>
      mountBody(opts)
        .find('[data-testid="panel-card-andamento"]')
        .findComponent(LeadReuniao)
        .exists();

    it('aparece em etapa de reunião (pelo label)', () => {
      expect(
        reuniaoVisivel({ props: { lead: { ...lead, lead_stage_id: 4 } } })
      ).toBe(true);
    });

    it('aparece quando a reunião (tarefa) já passou', () => {
      const tasks = [
        { id: 1, kind: 'meeting', due_at: '2020-01-01T10:00:00Z' },
      ];
      expect(reuniaoVisivel({ spies: { tasks } })).toBe(true);
    });

    it('aparece quando já há resultado registrado', () => {
      expect(
        reuniaoVisivel({
          props: { lead: { ...lead, reuniao_resultado: 'qualificada' } },
        })
      ).toBe(true);
    });

    it('não aparece sem reunião em jogo (reunião futura não conta)', () => {
      const tasks = [
        { id: 1, kind: 'meeting', due_at: '2999-01-01T10:00:00Z' },
      ];
      expect(reuniaoVisivel({ spies: { tasks } })).toBe(false);
    });
  });

  describe('resumo', () => {
    it('mostra telefone (copiável) e donos só depois de abrir "Dados do contato"; CPF fica só no editar tudo', async () => {
      const wrapper = mountBody();
      expect(wrapper.text()).not.toContain('Eduardo / Camila');
      await wrapper
        .find('[data-testid="contact-data-toggle"]')
        .trigger('click');
      expect(wrapper.text()).toContain('Eduardo / Camila');
      expect(wrapper.text()).not.toContain('052.318.774-90');
      await wrapper.find('[data-testid="contact-copy-phone"]').trigger('click');
      expect(copyTextToClipboard).toHaveBeenCalledWith('+55489999');
    });

    it('mostra o cartão Qualificação viva logo após o cartão Caso', () => {
      const wrapper = mountBody({
        props: { lead: { ...lead, thesis_id: 3 } },
      });
      expect(wrapper.findComponent({ name: 'QualificacaoViva' }).exists()).toBe(
        true
      );
    });

    it('Andamento: só a mini-esteira (etapa fica na pílula), chance rotulada e sem o valor', () => {
      const wrapper = mountBody();
      expect(wrapper.findComponent({ name: 'MiniEsteira' }).exists()).toBe(
        true
      );
      const card = wrapper.find('[data-testid="panel-card-andamento"]').text();
      expect(card).not.toContain('Novo');
      expect(card).toContain('RAMON.LEAD_PANEL.ANDAMENTO.CHANCE 10%');
      expect(card).not.toContain(formatBrl(48000));
    });

    it('cartão Documentos leva pra aba documentos', async () => {
      const wrapper = mountBody({
        props: {
          lead: { ...lead, thesis_id: 3, docs_total: 4, docs_received: 1 },
        },
      });
      await wrapper.find('[data-testid="panel-card-docs"]').trigger('click');
      expect(
        wrapper
          .find('[data-testid="lead-tab-documentos"]')
          .attributes('aria-selected')
      ).toBe('true');
    });

    it('expande o formulário completo pelo link "editar todos os campos" (dentro de Dados do contato)', async () => {
      const wrapper = mountBody();
      expect(wrapper.findComponent({ name: 'LeadFields' }).exists()).toBe(
        false
      );
      await wrapper
        .find('[data-testid="contact-data-toggle"]')
        .trigger('click');
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

    it('seções nativas da conversa ficam recolhidas atrás de "Mais da conversa"', async () => {
      const wrapper = mountBody();
      expect(
        wrapper.findComponent({ name: 'ConversationAction' }).exists()
      ).toBe(false);
      await wrapper
        .find('[data-testid="conversation-extras-toggle"]')
        .trigger('click');
      expect(
        wrapper.findComponent({ name: 'ConversationAction' }).exists()
      ).toBe(true);
      expect(wrapper.findComponent({ name: 'MacrosList' }).exists()).toBe(true);
    });

    it('no drawer não há "Não é lead" nem ações nativas da conversa', () => {
      const wrapper = mountBody({ props: { context: 'drawer' } });
      expect(wrapper.find('[data-testid="lead-discard"]').exists()).toBe(false);
      expect(
        wrapper.findComponent({ name: 'ConversationAction' }).exists()
      ).toBe(false);
    });
  });

  describe('temperatura e risco de esfriar', () => {
    const hotMessage = {
      message_type: 0,
      created_at: Math.floor(Date.now() / 1000) - 10 * 60,
      content: 'oi tudo bem por aí',
      private: false,
    };

    it('mostra o cartão Temperatura só na conversa, com mensagens do chat', () => {
      const wrapper = mountBody({
        spies: { chatMessages: [hotMessage] },
      });
      const card = wrapper.find('[data-testid="panel-card-termometro"]');
      expect(card.exists()).toBe(true);
      expect(card.text()).toContain('RAMON.TERMOMETRO.QUENTE');
    });

    it('sem mensagens incoming no chat, o cartão Temperatura não aparece', () => {
      const wrapper = mountBody();
      expect(
        wrapper.find('[data-testid="panel-card-termometro"]').exists()
      ).toBe(false);
    });

    it('no drawer não mostra o cartão Temperatura mesmo com mensagens', () => {
      const wrapper = mountBody({
        props: { context: 'drawer' },
        spies: { chatMessages: [hotMessage] },
      });
      expect(
        wrapper.find('[data-testid="panel-card-termometro"]').exists()
      ).toBe(false);
    });

    it('mostra o cartão Risco quando o lead está stalled', () => {
      const wrapper = mountBody({
        props: { lead: { ...lead, stalled: true } },
      });
      expect(wrapper.find('[data-testid="panel-card-risco"]').exists()).toBe(
        true
      );
    });

    it('sem stalled, o cartão Risco não aparece', () => {
      const wrapper = mountBody();
      expect(wrapper.find('[data-testid="panel-card-risco"]').exists()).toBe(
        false
      );
    });

    it('clicar em "Preparar retomada" dispara leads/followUpDraft', async () => {
      const followUpDraft = vi.fn();
      const wrapper = mountBody({
        props: { lead: { ...lead, stalled: true } },
        spies: { followUpDraft },
      });
      await wrapper
        .find('[data-testid="risco-preparar-retomada"]')
        .trigger('click');
      await flushPromises();
      expect(followUpDraft).toHaveBeenCalledWith(expect.anything(), 7);
      expect(useAlert).toHaveBeenCalledWith('RAMON.RISCO.PREPARADO');
    });

    it.each([
      ['no_conversation', 'RAMON.RISCO.RECUSA.NO_CONVERSATION'],
      ['open_follow_up', 'RAMON.RISCO.RECUSA.OPEN_FOLLOW_UP'],
      ['recent_follow_up', 'RAMON.RISCO.RECUSA.RECENT_FOLLOW_UP'],
      [undefined, 'RAMON.FUNIL.SAVE_ERROR'],
    ])(
      '422 com reason %s → avisa o motivo, não "em preparo"',
      async (reason, key) => {
        useAlert.mockClear();
        const followUpDraft = vi.fn().mockRejectedValue({
          response: { data: { reason, days_ago: 2, min_gap_days: 5 } },
        });
        const wrapper = mountBody({
          props: { lead: { ...lead, stalled: true } },
          spies: { followUpDraft },
        });
        await wrapper
          .find('[data-testid="risco-preparar-retomada"]')
          .trigger('click');
        await flushPromises();
        expect(useAlert).toHaveBeenCalledWith(key);
        expect(useAlert).not.toHaveBeenCalledWith('RAMON.RISCO.PREPARADO');
      }
    );

    it('lead sem conversa: sem botão, explica o porquê', () => {
      const wrapper = mountBody({
        props: { lead: { ...lead, stalled: true, conversation_id: null } },
      });
      expect(
        wrapper.find('[data-testid="risco-preparar-retomada"]').exists()
      ).toBe(false);
      expect(wrapper.find('[data-testid="risco-sem-conversa"]').text()).toBe(
        'RAMON.RISCO.RECUSA.NO_CONVERSATION'
      );
    });

    it('notas recarregam pelo follow_up_last_at do broadcast', () => {
      const wrapper = mountBody({
        props: { lead: { ...lead, follow_up_last_at: '2026-10-05T12:00:00Z' } },
      });
      const notas = wrapper.findComponent({ name: 'LeadNotes' });
      expect(notas.props('refreshKey')).toBe('2026-10-05T12:00:00Z-0');
      expect(notas.props('inConversation')).toBe(true);
    });

    it('Andamento mostra a última simulação e leva ao Simulador', async () => {
      const ultima = {
        mensal: 706,
        atrasados: 25416,
        em: '2026-10-02T15:00:00Z',
        parametros: { der: '2021-12-11' },
      };
      const wrapper = mountBody({
        props: {
          lead: { ...lead, custom_attributes: { ultima_simulacao: ultima } },
        },
      });
      const linha = wrapper.find('[data-testid="panel-ultima-simulacao"]');
      expect(linha.text()).toContain('RAMON.LEAD_PANEL.ANDAMENTO.LAST_SIM');
      expect(linha.text()).toContain(formatBrl(25416));
      expect(linha.text()).toContain(formatBrl(706));
      expect(linha.text()).toContain('02/10');
      await linha.trigger('click');
      const sim = wrapper.findComponent({ name: 'LeadSimulador' });
      expect(sim.exists()).toBe(true);
      expect(sim.props('ultimaSimulacao')).toEqual(ultima);
    });

    it('sem simulação, nenhuma linha no Andamento', () => {
      const wrapper = mountBody();
      expect(
        wrapper.find('[data-testid="panel-ultima-simulacao"]').exists()
      ).toBe(false);
    });

    it('risco continua funcional no drawer (a action é independente de contexto)', () => {
      const wrapper = mountBody({
        props: { context: 'drawer', lead: { ...lead, stalled: true } },
      });
      expect(wrapper.find('[data-testid="panel-card-risco"]').exists()).toBe(
        true
      );
    });
  });
});
