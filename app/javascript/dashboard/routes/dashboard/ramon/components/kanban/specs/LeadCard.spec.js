import { shallowMount } from '@vue/test-utils';
import LeadCard from '../LeadCard.vue';

const lead = {
  id: 10,
  name: 'João',
  conversation_id: 99,
  stage_name: 'Negociação',
  stage_color: '#f59e0b',
  benefit_type_name: 'Auxílio-acidente',
  lead_priority_name: 'Alta',
  value: '12000.50',
  closer_name: 'Eduardo Schlata',
};

const mountCard = (props = {}) =>
  shallowMount(LeadCard, {
    props: { lead, ...props },
    global: { mocks: { $t: k => k } },
  });

describe('LeadCard.vue', () => {
  it('renderiza nome, benefício e valor compacto dourado', () => {
    const wrapper = mountCard();
    expect(wrapper.text()).toContain('João');
    expect(wrapper.text()).toContain('Auxílio-acidente');
    const value = wrapper.find('[data-testid="lead-value"]');
    expect(value.text()).toMatch(/R\$\s?12\s?mil/);
    expect(value.classes()).toContain('text-n-iris-11');
  });

  it('mostra traço no lugar do valor quando o lead não tem valor', () => {
    const wrapper = mountCard({ lead: { ...lead, value: null } });
    const value = wrapper.find('[data-testid="lead-value"]');
    expect(value.text()).toBe('—');
    expect(value.classes()).not.toContain('text-n-iris-11');
  });

  it('emite open-lead ao clicar no corpo', async () => {
    const wrapper = mountCard();
    await wrapper.find('[data-testid="lead-card-body"]').trigger('click');
    expect(wrapper.emitted('openLead')[0][0]).toEqual(lead);
  });

  describe('linha de próxima ação', () => {
    it('tarefa vencida = dot/texto ruby', () => {
      const wrapper = mountCard({
        lead: {
          ...lead,
          next_task_due_at: '2020-01-01T09:00:00Z',
          next_task_title: 'Ligar pós-perícia',
        },
      });
      const action = wrapper.find('[data-testid="next-action"]');
      expect(action.exists()).toBe(true);
      expect(action.classes()).toContain('text-n-ruby-11');
    });

    it('reunião marcada = íris com data e hora, não contagem de dias', () => {
      const wrapper = mountCard({
        lead: {
          ...lead,
          next_task_due_at: new Date(Date.now() + 5 * 86400000).toISOString(),
          next_task_title: 'Reunião Cal.com: Primeiro Atendimento',
          next_task_kind: 'meeting',
        },
      });
      const action = wrapper.find('[data-testid="next-action"]');
      expect(action.classes()).toContain('text-n-iris-11');
      expect(action.text()).toContain('RAMON.KANBAN.CARD.NEXT_MEETING');
    });

    it('tarefa de hoje = âmbar', () => {
      // fim do dia local: sempre "hoje" e ainda no futuro
      const due = new Date();
      due.setHours(23, 59, 59, 0);
      const wrapper = mountCard({
        lead: { ...lead, next_task_due_at: due.toISOString() },
      });
      expect(wrapper.find('[data-testid="next-action"]').classes()).toContain(
        'text-n-amber-11'
      );
    });

    it('tarefa futura = teal', () => {
      const wrapper = mountCard({
        lead: {
          ...lead,
          next_task_due_at: new Date(Date.now() + 5 * 86400000).toISOString(),
        },
      });
      expect(wrapper.find('[data-testid="next-action"]').classes()).toContain(
        'text-n-teal-11'
      );
    });

    it('sem tarefa aberta mostra o alerta "sem próxima ação"', () => {
      const wrapper = mountCard({
        lead: { ...lead, open_tasks_count: 0, next_task_due_at: null },
      });
      const alert = wrapper.find('[data-testid="no-next-action"]');
      expect(alert.exists()).toBe(true);
      expect(alert.classes()).toContain('text-n-ruby-11');
    });
  });

  describe('checkbox de seleção em lote', () => {
    it('não renderiza quando selectable é false', () => {
      const wrapper = mountCard();
      expect(wrapper.find('[data-testid="select-toggle"]').exists()).toBe(
        false
      );
    });

    it('emite toggleSelect sem abrir o lead', async () => {
      const wrapper = mountCard({ selectable: true });
      await wrapper.find('[data-testid="select-toggle"]').trigger('click');
      expect(wrapper.emitted('toggleSelect')[0][0]).toEqual(lead);
      expect(wrapper.emitted('openLead')).toBeFalsy();
    });

    it('marca bronze quando selected', () => {
      const wrapper = mountCard({ selectable: true, selected: true });
      expect(wrapper.find('[data-testid="select-toggle"]').classes()).toContain(
        'bg-n-iris-9'
      );
    });
  });

  describe('ações rápidas do hover', () => {
    it('emite open-conversation com o id e não abre o lead', async () => {
      const wrapper = mountCard({ lead: { ...lead, conversation_id: 99 } });
      await wrapper.find('[data-testid="open-conversation"]').trigger('click');
      expect(wrapper.emitted('openConversation')[0]).toEqual([99]);
      expect(wrapper.emitted('openLead')).toBeFalsy();
    });

    it('esconde o botão de conversa sem conversation_id', () => {
      const wrapper = mountCard({ lead: { ...lead, conversation_id: null } });
      expect(wrapper.find('[data-testid="open-conversation"]').exists()).toBe(
        false
      );
    });

    it('emite openDossie com o lead', async () => {
      const wrapper = mountCard();
      await wrapper.find('[data-testid="open-dossie"]').trigger('click');
      expect(wrapper.emitted('openDossie')[0][0]).toEqual(lead);
      expect(wrapper.emitted('openLead')).toBeFalsy();
    });
  });

  describe('risco na borda esquerda', () => {
    it('prescrevendo (parcelas perdidas) = borda ruby', () => {
      const wrapper = mountCard({
        lead: { ...lead, dcb_em: '2019-01-01', benefit_monthly_value: 1412 },
      });
      expect(wrapper.classes()).toContain('border-l-n-ruby-9');
      expect(wrapper.classes()).toContain('border-l-[3px]');
    });

    it('parado (stalled) = borda âmbar', () => {
      const wrapper = mountCard({ lead: { ...lead, stalled: true } });
      expect(wrapper.classes()).toContain('border-l-n-amber-9');
    });

    it('sem risco = sem borda de 3px', () => {
      const wrapper = mountCard();
      expect(wrapper.classes()).not.toContain('border-l-[3px]');
    });
  });

  describe('pill de SLA de 1º contato', () => {
    const minute = 60000;

    it('dentro do SLA = pill âmbar com o tempo restante', () => {
      const wrapper = mountCard({
        lead: {
          ...lead,
          sla: {
            due_at: new Date(Date.now() + 41 * minute).toISOString(),
            replied_at: null,
            minutes: 60,
          },
        },
      });
      const pill = wrapper.find('[data-testid="sla-pill"]');
      expect(pill.exists()).toBe(true);
      expect(pill.text()).toBe('41min');
      expect(pill.classes()).toContain('text-n-amber-11');
      // dentro do SLA não muda a borda nem mostra o CTA
      expect(wrapper.classes()).not.toContain('border-l-n-ruby-9');
    });

    it('estourado = pill ruby, borda ruby e CTA "Responder agora"', async () => {
      const wrapper = mountCard({
        lead: {
          ...lead,
          sla: {
            due_at: new Date(Date.now() - 167 * minute).toISOString(),
            replied_at: null,
            minutes: 60,
          },
        },
      });
      const pill = wrapper.find('[data-testid="sla-pill"]');
      expect(pill.text()).toBe('2h 47min');
      expect(pill.classes()).toContain('bg-n-ruby-9');
      expect(wrapper.classes()).toContain('border-l-n-ruby-9');
      await wrapper.find('[data-testid="sla-respond-now"]').trigger('click');
      expect(wrapper.emitted('openConversation')[0]).toEqual([99]);
    });

    it('respondido = pill teal com o tempo até a 1ª resposta', () => {
      const due = Date.now();
      const wrapper = mountCard({
        lead: {
          ...lead,
          sla: {
            due_at: new Date(due).toISOString(),
            // começou em due-60min; respondeu 12min depois do início
            replied_at: new Date(due - 48 * minute).toISOString(),
            minutes: 60,
          },
        },
      });
      const pill = wrapper.find('[data-testid="sla-pill"]');
      expect(pill.exists()).toBe(true);
      expect(pill.text()).toContain('12min');
      expect(pill.classes()).toContain('text-n-teal-11');
    });

    it('lead sem sla não mostra pill nem CTA', () => {
      const wrapper = mountCard();
      expect(wrapper.find('[data-testid="sla-pill"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="sla-respond-now"]').exists()).toBe(
        false
      );
    });
  });

  it('shows the awaiting-human triage badge when the latest triage awaits a human', () => {
    const wrapper = mountCard({
      lead: { ...lead, latest_triage: { id: 1, status: 'awaiting_human' } },
    });
    const badge = wrapper.find('[data-testid="triage-awaiting-human-badge"]');
    expect(badge.exists()).toBe(true);
    expect(badge.text()).toContain('RAMON.KANBAN.CARD.TRIAGE_AWAITING_HUMAN');
  });

  it('shows the follow-up badge with count when follow_up_count > 0', () => {
    const wrapper = mountCard({
      lead: {
        ...structuredClone(lead),
        follow_up_count: 2,
        follow_up_last_at: '2026-07-20T12:00:00Z',
      },
    });
    const badge = wrapper.find('[data-testid="follow-up-badge"]');
    expect(badge.exists()).toBe(true);
    expect(badge.text()).toContain('2');
  });

  it('hides the follow-up badge when follow_up_count is 0', () => {
    const wrapper = mountCard({
      lead: { ...structuredClone(lead), follow_up_count: 0 },
    });
    expect(wrapper.find('[data-testid="follow-up-badge"]').exists()).toBe(
      false
    );
  });

  it('hides the awaiting-human badge for done triages', () => {
    const wrapper = mountCard({
      lead: {
        ...lead,
        latest_triage: { id: 1, status: 'done', viability: 'alta' },
      },
    });
    expect(
      wrapper.find('[data-testid="triage-awaiting-human-badge"]').exists()
    ).toBe(false);
  });
});
