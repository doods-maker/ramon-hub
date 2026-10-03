import { mount, flushPromises } from '@vue/test-utils';
import RamonHojeAPI from 'dashboard/api/ramonHoje';
import Hoje from '../Hoje.vue';
import HojeRecepcao from '../../components/hoje/HojeRecepcao.vue';
import HojeComercial from '../../components/hoje/HojeComercial.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/api/ramonHoje', () => ({ default: { get: vi.fn() } }));

const montar = async () => {
  const wrapper = mount(Hoje, { shallow: true });
  await flushPromises();
  return wrapper;
};

describe('Hoje', () => {
  it('escolhe o desenho pelo papel que o backend mandou', async () => {
    RamonHojeAPI.get.mockResolvedValue({
      data: {
        papel: 'recepcao',
        data: '2026-10-03',
        sem_responsavel: [],
        atendimentos: [],
        caixa: {},
        advbox_fora: false,
      },
    });
    const w = await montar();
    expect(w.findComponent(HojeRecepcao).exists()).toBe(true);
    expect(w.text()).toContain('sábado, 3 de outubro');
  });

  it('papel sem desenho próprio (sdr, closer, equipe) cai no comercial', async () => {
    RamonHojeAPI.get.mockResolvedValue({
      data: { papel: 'equipe', data: '2026-10-03' },
    });
    const w = await montar();
    expect(w.findComponent(HojeComercial).exists()).toBe(true);
  });

  it('falhou: mostra o erro e tenta de novo', async () => {
    RamonHojeAPI.get.mockRejectedValueOnce(new Error('x'));
    const w = await montar();
    expect(w.find('[data-testid="hoje-erro"]').text()).toContain(
      'RAMON.HOJE.ERRO'
    );
    RamonHojeAPI.get.mockResolvedValue({
      data: { papel: 'sdr', data: '2026-10-03' },
    });
    await w.find('[data-testid="hoje-erro"] button').trigger('click');
    await flushPromises();
    expect(w.find('[data-testid="hoje-erro"]').exists()).toBe(false);
    expect(w.findComponent(HojeComercial).exists()).toBe(true);
  });
});
