import { mount } from '@vue/test-utils';
import SeloPrazo from '../SeloPrazo.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

describe('SeloPrazo', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-10-03T13:00:00Z'));
  });
  afterEach(() => vi.useRealTimers());

  const prazo = segundos =>
    new Date(Date.now() + segundos * 1000).toISOString();

  it('cinza com mais de 2 min', () => {
    const w = mount(SeloPrazo, { props: { prazoEm: prazo(252) } });
    expect(w.text()).toContain('4:12');
    expect(w.classes()).toContain('text-n-slate-11');
  });

  it('âmbar faltando 2 min ou menos', () => {
    const w = mount(SeloPrazo, { props: { prazoEm: prazo(108) } });
    expect(w.text()).toContain('1:48');
    expect(w.classes()).toContain('text-n-amber-11');
  });

  it('vermelho com +tempo depois do prazo, e anda sozinho', async () => {
    const w = mount(SeloPrazo, { props: { prazoEm: prazo(-185) } });
    expect(w.text()).toContain('+3:05');
    expect(w.classes()).toContain('text-n-ruby-11');
    expect(w.attributes('title')).toBe('RAMON.HOJE.PRAZO_PASSOU');
    vi.advanceTimersByTime(1000);
    await w.vm.$nextTick();
    expect(w.text()).toContain('+3:06');
  });
});
