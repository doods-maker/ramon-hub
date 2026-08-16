import { ref } from 'vue';
import { useTemperatura } from '../useTemperatura';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const msg = (type, minutesAgo, content = 'oi tudo bem por aí') => ({
  message_type: type, // 0 incoming, 1 outgoing
  created_at: Math.floor(Date.now() / 1000) - minutesAgo * 60,
  content,
  private: false,
});

describe('useTemperatura', () => {
  it('incoming recente (<60min) e ritmo curto → quente', () => {
    const { nivel } = useTemperatura(
      ref([msg(1, 90), msg(0, 30), msg(1, 20), msg(0, 10)])
    );
    expect(nivel.value).toBe('quente');
  });

  it('última incoming velha (>24h) → fria', () => {
    const { nivel } = useTemperatura(ref([msg(0, 60 * 30)]));
    expect(nivel.value).toBe('fria');
  });

  it('sinal "vou pensar" numa incoming recente rebaixa pra morna', () => {
    const { nivel } = useTemperatura(
      ref([msg(0, 10, 'vou pensar mais um pouco')])
    );
    expect(nivel.value).toBe('morna');
  });

  it('sem incoming → null (sem cartão)', () => {
    const { nivel } = useTemperatura(ref([msg(1, 10)]));
    expect(nivel.value).toBeNull();
  });
});
