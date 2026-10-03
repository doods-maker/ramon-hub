import { flushPromises, mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import PecaPainel from '../../components/conteudo/PecaPainel.vue';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';

vi.mock('dashboard/api/ramonConteudo', () => ({
  default: {
    show: vi.fn(),
    agendar: vi.fn(),
    publicarAgora: vi.fn(),
    atualizarLegenda: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const montada = {
  id: 3,
  status: 'montado',
  gancho: 'G',
  legenda: 'L',
  imagens: ['a.jpg'],
  conteudo: {},
  sugestao_horario: '2026-10-07T15:00:00Z',
};

describe('PecaPainel agenda', () => {
  beforeEach(() => vi.clearAllMocks());

  it('pré-preenche a sugestão e agenda com o horário do campo', async () => {
    RamonConteudoAPI.show.mockResolvedValue({ data: montada });
    RamonConteudoAPI.agendar.mockResolvedValue({
      data: { ...montada, status: 'agendado' },
    });
    const w = mount(PecaPainel, { props: { pecaId: 3 } });
    await flushPromises();
    const campo = w.find('[data-testid="agendar-quando"]');
    expect(campo.element.value).not.toBe('');
    await w.find('[data-testid="agendar"]').trigger('click');
    expect(RamonConteudoAPI.agendar).toHaveBeenCalledWith(
      3,
      new Date(campo.element.value).toISOString()
    );
  });

  it('salva a legenda editada antes de agendar', async () => {
    const ordem = [];
    RamonConteudoAPI.show.mockResolvedValue({ data: montada });
    RamonConteudoAPI.atualizarLegenda.mockImplementation(async () => {
      ordem.push('legenda');
      return { data: { ...montada, legenda: 'Nova' } };
    });
    RamonConteudoAPI.agendar.mockImplementation(async () => {
      ordem.push('agendar');
      return { data: { ...montada, status: 'agendado' } };
    });
    const w = mount(PecaPainel, { props: { pecaId: 3 } });
    await flushPromises();
    await w.find('textarea').setValue('Nova');
    await w.find('[data-testid="agendar"]').trigger('click');
    await flushPromises();
    expect(RamonConteudoAPI.atualizarLegenda).toHaveBeenCalledWith(3, 'Nova');
    expect(ordem).toEqual(['legenda', 'agendar']);
  });
});
