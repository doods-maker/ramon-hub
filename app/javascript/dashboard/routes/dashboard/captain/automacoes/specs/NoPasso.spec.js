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

describe('NoPasso — saída tomada', () => {
  it('acende só o rótulo da saída tomada', () => {
    const w = montar({ saidaTomada: 'sim' });
    const [sim, nao] = w.findAll('span.font-mono');
    expect(sim.classes()).toContain('text-n-teal-11');
    expect(nao.classes()).not.toContain('text-n-teal-11');
  });
});
