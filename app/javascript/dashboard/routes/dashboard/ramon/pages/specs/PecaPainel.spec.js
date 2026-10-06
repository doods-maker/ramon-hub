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
    tentarDeNovo: vi.fn(),
    voltarProntas: vi.fn(),
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

const montar = (props = {}) =>
  mount(PecaPainel, {
    props: { pecaId: 3, ...props },
    global: { mocks: { $t: key => key } },
  });

describe('PecaPainel publicação', () => {
  beforeEach(() => vi.clearAllMocks());

  it('publicar agora pede confirmação antes de chamar a API', async () => {
    RamonConteudoAPI.show.mockResolvedValue({ data: montada });
    RamonConteudoAPI.publicarAgora.mockResolvedValue({
      data: { ...montada, status: 'agendado' },
    });
    const w = montar();
    await flushPromises();
    await w.find('[data-testid="publicar-agora"]').trigger('click');
    expect(RamonConteudoAPI.publicarAgora).not.toHaveBeenCalled();
    await w.find('[data-testid="confirm-modal-confirm"]').trigger('click');
    await flushPromises();
    expect(RamonConteudoAPI.publicarAgora).toHaveBeenCalledWith(3);
  });

  it('falha ambígua só libera tentar de novo depois do "conferi"', async () => {
    const falhou = { ...montada, status: 'falhou', ambigua: true, erro: 'x' };
    RamonConteudoAPI.show.mockResolvedValue({ data: falhou });
    RamonConteudoAPI.tentarDeNovo.mockResolvedValue({
      data: { ...falhou, status: 'agendado' },
    });
    const w = montar();
    await flushPromises();
    const botao = () => w.find('[data-testid="tentar-de-novo"]');
    expect(botao().attributes('disabled')).toBeDefined();
    await w.find('[data-testid="conferi-instagram"]').setValue(true);
    expect(botao().attributes('disabled')).toBeUndefined();
    await botao().trigger('click');
    await w.find('[data-testid="confirm-modal-confirm"]').trigger('click');
    await flushPromises();
    expect(RamonConteudoAPI.tentarDeNovo).toHaveBeenCalledWith(3, true);
  });
});

describe('PecaPainel token, falha e legenda', () => {
  beforeEach(() => vi.clearAllMocks());

  it('sem token do IG bloqueia agendar e publicar', async () => {
    RamonConteudoAPI.show.mockResolvedValue({ data: montada });
    const w = montar({ tokenIg: false });
    await flushPromises();
    expect(w.text()).toContain('RAMON.CONTEUDO.SEM_TOKEN');
    expect(
      w.find('[data-testid="agendar"]').attributes('disabled')
    ).toBeDefined();
    expect(
      w.find('[data-testid="publicar-agora"]').attributes('disabled')
    ).toBeDefined();
  });

  it('peça que falhou volta pra Prontas', async () => {
    const falhou = { ...montada, status: 'falhou', erro: 'x' };
    RamonConteudoAPI.show.mockResolvedValue({ data: falhou });
    RamonConteudoAPI.voltarProntas.mockResolvedValue({ data: montada });
    const w = montar();
    await flushPromises();
    await w.find('[data-testid="voltar-prontas"]').trigger('click');
    await flushPromises();
    expect(RamonConteudoAPI.voltarProntas).toHaveBeenCalledWith(3, false);
    expect(w.emitted('changed')).toBeTruthy();
  });

  it('contador da legenda fica ruby no limite de hashtags', async () => {
    RamonConteudoAPI.show.mockResolvedValue({ data: montada });
    const w = montar();
    await flushPromises();
    const tags = Array.from({ length: 30 }, (_, i) => `#t${i}`).join(' ');
    await w.find('textarea').setValue(tags);
    const contador = w.findAll('[data-testid="legenda-contador"] span');
    expect(contador[0].classes()).toContain('text-n-slate-10');
    expect(contador[1].classes()).toContain('text-n-ruby-11');
  });
});
