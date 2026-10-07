import { mount } from '@vue/test-utils';
import NoPasso from '../NoPasso.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: [] }),
}));

const montar = props =>
  mount(NoPasso, {
    props: {
      id: 'n1',
      tipo: 'se',
      config: { condicoes: [] },
      estado: 'aceso',
      somenteLeitura: true,
      ...props,
    },
    global: { stubs: { Handle: true } },
  });

describe('NoPasso — webhook', () => {
  it('mostra só o host, sem caminho nem token', () => {
    const w = montar({
      tipo: 'webhook',
      config: { url: 'https://hook.make.com/abc123?token=x' },
    });
    expect(w.text()).toContain('hook.make.com');
    expect(w.text()).not.toContain('abc123');
    expect(w.text()).not.toContain('token');
  });
});

describe('NoPasso — esperar', () => {
  it('singular com 1 (1 dia, não "1 dias")', () => {
    const um = montar({
      tipo: 'esperar',
      config: { quantidade: 1, unidade: 'dias' },
    });
    const dois = montar({
      tipo: 'esperar',
      config: { quantidade: 2, unidade: 'dias' },
    });
    expect(um.text()).toMatch(/1 day\b/);
    expect(dois.text()).toMatch(/2 days/);
  });
  it('antes da reunião diz que conta para trás', () => {
    const w = montar({
      tipo: 'esperar',
      config: { antes_de: 'reuniao', quantidade: 24, unidade: 'horas' },
    });
    expect(w.text()).toContain('24 hours before the meeting');
  });

  it('SLA da caixa e "depois da criação da conversa" (B4.2)', () => {
    const sla = montar({
      tipo: 'esperar',
      config: { desde: 'conversa', prazo: 'sla_caixa' },
    });
    const conversa = montar({
      tipo: 'esperar',
      config: { desde: 'conversa', quantidade: 60, unidade: 'minutos' },
    });
    expect(sla.text()).toContain('The inbox SLA');
    expect(conversa.text()).toContain(
      '60 minutes after the conversation was created'
    );
  });
});

describe('NoPasso — saída tomada', () => {
  it('acende só o rótulo da saída tomada', () => {
    const w = montar({ saidaTomada: 'sim' });
    const [sim, nao] = w.findAll('span.font-mono');
    expect(sim.classes()).toContain('text-n-teal-11');
    expect(nao.classes()).not.toContain('text-n-teal-11');
  });
});

describe('NoPasso — rotina', () => {
  it('mostra o nome da rotina escolhida', () => {
    const w = montar({
      tipo: 'rotina',
      config: { rotina: 'abrir_caso_advbox' },
    });
    expect(w.text()).toContain('Open the case in ADVBOX');
  });
});
