import { mount, RouterLinkStub } from '@vue/test-utils';
import HojeGestor from '../HojeGestor.vue';
import HojeAdvogada from '../HojeAdvogada.vue';
import AlertaCaixa from '../AlertaCaixa.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k, p) => (p?.nomes ? `${k}:${p.nomes}` : k) }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: 5 }),
}));
vi.mock('dashboard/stores/chegadas', () => ({
  useChegadasStore: () => ({
    itens: [
      {
        id: 1,
        cliente_nome: 'Neusa',
        motivo: 'atendimento 14:00',
        estado: 'aguardando',
        created_at: '2026-10-03T16:55:00Z',
        destinatario: { id: 5 },
      },
      {
        id: 2,
        cliente_nome: 'Outra',
        estado: 'aguardando',
        created_at: '2026-10-03T16:55:00Z',
        destinatario: { id: 9 },
      },
    ],
  }),
}));

const global = { stubs: { 'router-link': RouterLinkStub } };

describe('HojeGestor', () => {
  it('alertas, time, mês e funil', () => {
    const w = mount(HojeGestor, {
      global,
      props: {
        dados: {
          papel: 'gestor',
          data: '2026-10-03',
          precisa: [
            { tipo: 'sla', nivel: 'bad', count: 2, nomes: ['Rosane', 'Paulo'] },
            { tipo: 'conteudo', nivel: 'act', count: 1, nomes: ['Quem tem'] },
          ],
          time: {
            sdr: { respondidos: 11, media_minutos: 3.6667 },
            closer: { reunioes: 3, contratos: 1 },
            recepcao: { chegadas: 2 },
          },
          mes: {
            contratos: 7,
            meta_contratos: 13,
            reunioes_qualificadas: 18,
            docs_completos: 4,
            ganhos_mes: 7,
          },
          funil: [{ etapa: 'Novo', cor: '#6b7280', count: 8 }],
        },
      },
    });
    const alertas = w.findAllComponents(AlertaCaixa);
    expect(alertas).toHaveLength(2);
    expect(alertas[0].text()).toContain('Rosane e Paulo');
    expect(alertas[0].findComponent(RouterLinkStub).props('to').name).toBe(
      'ramon_esteira'
    );
    expect(alertas[1].text()).toContain('“Quem tem”.');
    expect(w.text()).toContain('3m40s');
    expect(w.text()).toContain('Outubro');
    expect(w.text()).toContain('Novo');
  });

  it('nada pendente mostra o vazio', () => {
    const w = mount(HojeGestor, {
      global,
      props: {
        dados: {
          papel: 'gestor',
          data: '2026-10-03',
          precisa: [],
          time: {
            sdr: { respondidos: 0, media_minutos: null },
            closer: { reunioes: 0, contratos: 0 },
            recepcao: { chegadas: 0 },
          },
          mes: {
            contratos: 0,
            meta_contratos: null,
            reunioes_qualificadas: 0,
            docs_completos: 0,
            ganhos_mes: 0,
          },
          funil: [],
        },
      },
    });
    expect(w.text()).toContain('RAMON.HOJE.PRECISA_VAZIO');
    expect(w.text()).toContain('—');
  });
});

describe('HojeAdvogada', () => {
  it('atribuídas, semana com destaque e só as chegadas pra ela', () => {
    const w = mount(HojeAdvogada, {
      global,
      props: {
        dados: {
          papel: 'advogada',
          data: '2026-10-03',
          atribuidas: [
            {
              conversa_id: 3,
              nome: 'Maria',
              cliente: true,
              ultima_mensagem: 'oi',
              esperando_desde: new Date().toISOString(),
            },
          ],
          semana: [
            {
              data: '2026-10-07',
              hora: '09:00',
              tarefa: 'ACOMPANHAR PERÍCIA',
              destaque: 'pericia',
              cliente: 'MARIA',
              processo: '5003412-18.2024.4.04.7207',
              notas: 'INSS Tubarão',
            },
          ],
          advbox_fora: false,
        },
      },
    });
    expect(w.text()).toContain('RAMON.HOJE.NOVA');
    expect(w.text()).toContain('07/10');
    expect(w.text()).toContain('RAMON.HOJE.DESTAQUE.pericia');
    expect(w.text()).toContain('5003412-18.2024.4.04.7207');
    expect(w.text()).toContain('Neusa');
    expect(w.text()).not.toContain('Outra');
  });

  it('ADVBOX fora avisa e mantém as conversas', () => {
    const w = mount(HojeAdvogada, {
      global,
      props: {
        dados: {
          papel: 'advogada',
          data: '2026-10-03',
          atribuidas: [],
          semana: null,
          advbox_fora: true,
        },
      },
    });
    expect(w.find('[data-testid="advbox-fora"]').exists()).toBe(true);
    expect(w.text()).toContain('RAMON.HOJE.ATRIBUIDAS_VAZIO');
  });
});
