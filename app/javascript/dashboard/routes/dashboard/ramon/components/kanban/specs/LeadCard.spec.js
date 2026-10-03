import { shallowMount } from '@vue/test-utils';
import LeadCard from '../LeadCard.vue';
import Selo from '../../hoje/Selo.vue';
import SeloPrazo from '../../hoje/SeloPrazo.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, vars) => (vars ? `${key} ${JSON.stringify(vars)}` : key),
  }),
}));

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

const TARDE = 'shadow-[inset_3px_0_0_rgb(var(--ruby-9))]';
const PARADO = 'shadow-[inset_3px_0_0_rgb(var(--amber-9))]';

const mountCard = (props = {}) =>
  shallowMount(LeadCard, {
    props: { lead, ...props },
    global: {
      mocks: { $t: (k, v) => (v ? `${k} ${JSON.stringify(v)}` : k) },
      renderStubDefaultSlot: true,
    },
  });

describe('LeadCard.vue', () => {
  it('renderiza nome, tese (cai pro benefício), valor mono e iniciais', () => {
    const wrapper = mountCard();
    expect(wrapper.text()).toContain('João');
    expect(wrapper.text()).toContain('Auxílio-acidente');
    expect(wrapper.text()).toContain('ES');
    const value = wrapper.find('[data-testid="lead-value"]');
    expect(value.text()).toMatch(/R\$\s?12\s?mil/);
    expect(value.classes()).toContain('font-mono');
  });

  it('tese do lead tem prioridade sobre o benefício', () => {
    const wrapper = mountCard({
      lead: { ...lead, thesis_name: 'Aposentadoria especial' },
    });
    expect(wrapper.text()).toContain('Aposentadoria especial');
    expect(wrapper.text()).not.toContain('Auxílio-acidente');
  });

  it('sem valor não mostra o valor', () => {
    const wrapper = mountCard({ lead: { ...lead, value: null } });
    expect(wrapper.find('[data-testid="lead-value"]').exists()).toBe(false);
  });

  it('emite open-lead ao clicar no corpo', async () => {
    const wrapper = mountCard();
    await wrapper.find('[data-testid="lead-card-body"]').trigger('click');
    expect(wrapper.emitted('openLead')[0][0]).toEqual(lead);
  });

  describe('selo de documentos', () => {
    it('incompleto = âmbar "docs 2/5"', () => {
      const wrapper = mountCard({
        lead: { ...lead, docs_received: 2, docs_total: 5 },
      });
      const selo = wrapper.findComponent(Selo);
      expect(selo.props('tom')).toBe('warn');
      expect(selo.text()).toContain('"received":2');
    });

    it('completo = verde', () => {
      const wrapper = mountCard({
        lead: { ...lead, docs_received: 5, docs_total: 5 },
      });
      expect(wrapper.findComponent(Selo).props('tom')).toBe('ok');
    });

    it('tese sem checklist não mostra selo', () => {
      const wrapper = mountCard({
        lead: { ...lead, docs_received: 0, docs_total: 0 },
      });
      expect(wrapper.find('[data-testid="docs-badge"]').exists()).toBe(false);
    });
  });

  describe('tempo quieto à direita do nome', () => {
    it('reunião marcada mostra dia e hora, não o título', () => {
      const due = new Date(Date.now() + 5 * 86400000);
      due.setUTCHours(17, 30, 0, 0);
      const wrapper = mountCard({
        lead: {
          ...lead,
          next_task_due_at: due.toISOString(),
          next_task_title: 'Reunião Cal.com: Primeiro Atendimento',
          next_task_kind: 'meeting',
        },
      });
      const quiet = wrapper.find('[data-testid="lead-quiet"]');
      expect(quiet.text()).toContain('14:30'); // fuso do escritório
      expect(wrapper.text()).not.toContain('Reunião Cal.com');
    });

    it('sem reunião mostra há quanto tempo está na etapa', () => {
      const wrapper = mountCard({
        lead: {
          ...lead,
          stage_entered_at: new Date(Date.now() - 5 * 3600000).toISOString(),
        },
      });
      expect(wrapper.find('[data-testid="lead-quiet"]').text()).toBe(
        'RAMON.HOJE.HORAS {"count":5}'
      );
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

    it('marca azul quando selected', () => {
      const wrapper = mountCard({ selectable: true, selected: true });
      expect(wrapper.find('[data-testid="select-toggle"]').classes()).toContain(
        'bg-n-blue-9'
      );
    });
  });

  describe('ações do rodapé', () => {
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

    it('ganho com docs pendentes: "Cobrar documentos" emite cobrarDocs e mantém o Dossiê', async () => {
      const wrapper = mountCard({
        lead: {
          ...lead,
          won_at: '2026-09-25T10:00:00Z',
          docs_received: 3,
          docs_total: 5,
        },
      });
      expect(wrapper.find('[data-testid="open-dossie"]').exists()).toBe(true);
      await wrapper.find('[data-testid="charge-docs"]').trigger('click');
      expect(wrapper.emitted('cobrarDocs')[0][0].id).toBe(10);
      expect(wrapper.emitted('openLead')).toBeFalsy();
    });
  });

  describe('selos dos filtros do funil', () => {
    beforeEach(() => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date('2026-10-03T12:00:00Z'));
    });
    afterEach(() => vi.useRealTimers());

    it('prescrição: % do prazo, DCB e "Perdemos" no lead perdido', () => {
      const wrapper = mountCard({
        filtro: 'prescricao',
        lead: { ...lead, dcb_em: '2023-01-10', lost_at: '2026-05-01' },
      });
      expect(wrapper.find('[data-testid="radar-pct"]').text()).toContain(
        '"pct":73'
      );
      expect(wrapper.text()).toContain('10/01/23');
      expect(wrapper.find('[data-testid="radar-lost-chip"]').exists()).toBe(
        true
      );
    });

    it('sem o filtro o card não mostra o selo do radar', () => {
      const wrapper = mountCard({ lead: { ...lead, dcb_em: '2023-01-10' } });
      expect(wrapper.find('[data-testid="radar-pct"]').exists()).toBe(false);
    });

    it('pós-venda: dias desde o ganho, âmbar passando de 7', () => {
      const ganho = { ...lead, won_at: '2026-09-23T12:00:00Z' };
      const wrapper = mountCard({ filtro: 'pos_venda', lead: ganho });
      const dias = wrapper.find('[data-testid="dias-ganho"]');
      expect(dias.text()).toContain('"dias":10');
      expect(dias.classes()).toContain('text-n-amber-11');
    });
  });

  describe('risco na borda esquerda', () => {
    it('prescrevendo (parcelas perdidas) = filete ruby e selo ruim', () => {
      const wrapper = mountCard({
        lead: { ...lead, dcb_em: '2019-01-01', benefit_monthly_value: 1412 },
      });
      expect(wrapper.classes()).toContain(TARDE);
      expect(
        wrapper.find('[data-testid="prescription-badge"]').attributes('tom')
      ).toBe('bad');
    });

    it('parado (stalled) = filete âmbar', () => {
      const wrapper = mountCard({ lead: { ...lead, stalled: true } });
      expect(wrapper.classes()).toContain(PARADO);
    });

    it('sem risco = sem filete', () => {
      const wrapper = mountCard();
      expect(wrapper.classes()).not.toContain(TARDE);
      expect(wrapper.classes()).not.toContain(PARADO);
    });
  });

  describe('prazo de 1ª resposta', () => {
    const minute = 60000;

    it('correndo = SeloPrazo com o vencimento, sem filete nem CTA', () => {
      const due = new Date(Date.now() + 4 * minute).toISOString();
      const wrapper = mountCard({
        lead: { ...lead, sla: { due_at: due, replied_at: null, minutes: 5 } },
      });
      expect(wrapper.findComponent(SeloPrazo).props('prazoEm')).toBe(due);
      expect(wrapper.classes()).not.toContain(TARDE);
      expect(wrapper.find('[data-testid="sla-respond-now"]').exists()).toBe(
        false
      );
    });

    it('estourado = filete ruby e CTA "Responder agora"', async () => {
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
      expect(wrapper.findComponent(SeloPrazo).exists()).toBe(true);
      expect(wrapper.classes()).toContain(TARDE);
      await wrapper.find('[data-testid="sla-respond-now"]').trigger('click');
      expect(wrapper.emitted('openConversation')[0]).toEqual([99]);
    });

    it('respondido ou sem sla não mostra o selo de prazo', () => {
      const replied = mountCard({
        lead: {
          ...lead,
          sla: {
            due_at: new Date().toISOString(),
            replied_at: new Date().toISOString(),
            minutes: 5,
          },
        },
      });
      expect(replied.findComponent(SeloPrazo).exists()).toBe(false);
      expect(mountCard().findComponent(SeloPrazo).exists()).toBe(false);
    });
  });
});
