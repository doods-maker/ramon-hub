import { flushPromises, mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import Conteudo from '../Conteudo.vue';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';

vi.mock('dashboard/api/ramonConteudo', () => ({ default: { get: vi.fn() } }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const peca = (id, status, extra = {}) => ({
  id,
  status,
  gancho: `Peça ${id}`,
  tipo: 'carrossel',
  tese: 'bpc',
  capa: null,
  travada: false,
  ...extra,
});

describe('Conteudo', () => {
  it('distribui as peças nas 5 colunas', async () => {
    RamonConteudoAPI.get.mockResolvedValue({
      data: {
        payload: [
          peca(1, 'rascunho'),
          peca(2, 'montando'),
          peca(3, 'montado'),
          peca(4, 'falhou'),
          peca(5, 'publicado'),
        ],
      },
    });
    const wrapper = mount(Conteudo, {
      global: { stubs: { PecaPainel: true, RamonPageHeader: true } },
    });
    await flushPromises();
    const ids = col =>
      wrapper.findAll(`[data-testid="coluna-${col}"] [data-testid="peca-card"]`)
        .length;
    expect([
      ids('pauta'),
      ids('montando'),
      ids('prontas'),
      ids('agendadas'),
      ids('publicadas'),
    ]).toEqual([1, 1, 1, 1, 1]);
  });

  it('marca peça travada', async () => {
    RamonConteudoAPI.get.mockResolvedValue({
      data: { payload: [peca(1, 'montando', { travada: true })] },
    });
    const wrapper = mount(Conteudo, {
      global: { stubs: { PecaPainel: true, RamonPageHeader: true } },
    });
    await flushPromises();
    expect(wrapper.find('[data-testid="peca-travada"]').exists()).toBe(true);
  });

  it('avisa no topo quando o token do IG não está configurado', async () => {
    RamonConteudoAPI.get.mockResolvedValue({
      data: { payload: [], token_ig: false },
    });
    const wrapper = mount(Conteudo, {
      global: { stubs: { PecaPainel: true, RamonPageHeader: true } },
    });
    await flushPromises();
    expect(wrapper.find('[data-testid="sem-token"]').exists()).toBe(true);
  });

  it('recarrega a cada 30s enquanto houver peça agendada e para sem nenhuma', async () => {
    vi.useFakeTimers();
    RamonConteudoAPI.get.mockClear();
    RamonConteudoAPI.get.mockResolvedValue({
      data: { payload: [peca(1, 'agendado')], token_ig: true },
    });
    const wrapper = mount(Conteudo, {
      global: { stubs: { PecaPainel: true, RamonPageHeader: true } },
    });
    await flushPromises();
    expect(RamonConteudoAPI.get).toHaveBeenCalledTimes(1);

    RamonConteudoAPI.get.mockResolvedValue({
      data: { payload: [peca(1, 'publicado')], token_ig: true },
    });
    await vi.advanceTimersByTimeAsync(30 * 1000);
    expect(RamonConteudoAPI.get).toHaveBeenCalledTimes(2);

    // sem peça em andamento: o timer parou
    await vi.advanceTimersByTimeAsync(90 * 1000);
    expect(RamonConteudoAPI.get).toHaveBeenCalledTimes(2);
    wrapper.unmount();
    vi.useRealTimers();
  });
});
