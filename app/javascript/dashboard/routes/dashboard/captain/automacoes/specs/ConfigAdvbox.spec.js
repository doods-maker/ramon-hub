import { mount, flushPromises } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import ConfigAdvbox from '../ConfigAdvbox.vue';

vi.mock('dashboard/api/ramonFluxos', () => ({
  default: { opcoesAdvbox: vi.fn() },
}));

describe('ConfigAdvbox', () => {
  it('tarefa: carrega tipos e responsáveis do ADVBOX e grava os IDs', async () => {
    RamonFluxosAPI.opcoesAdvbox.mockResolvedValue({
      data: {
        usuarios: [{ id: 266778, nome: 'EDUARDO SCHLATA' }],
        tipos_tarefa: [{ id: 8745408, nome: 'AGUARDANDO DOCUMENTOS CLIENTE' }],
      },
    });
    const w = mount(ConfigAdvbox, { props: { config: { acao: 'tarefa' } } });
    await flushPromises();
    await w.find('[data-testid="advbox-tipo"]').setValue('8745408');
    expect(w.emitted('update:config').at(-1)).toEqual([
      { acao: 'tarefa', tipo_tarefa_id: 8745408 },
    ]);
    await w.find('[data-testid="advbox-responsavel"]').setValue('266778');
    expect(w.emitted('update:config').at(-1)).toEqual([
      { acao: 'tarefa', responsavel_id: 266778 },
    ]);
  });

  it('movimentação não pede tipo nem responsável', async () => {
    RamonFluxosAPI.opcoesAdvbox.mockResolvedValue({
      data: { usuarios: [], tipos_tarefa: [] },
    });
    const w = mount(ConfigAdvbox, {
      props: { config: { acao: 'movimentacao' } },
    });
    await flushPromises();
    expect(w.find('[data-testid="advbox-tipo"]').exists()).toBe(false);
    expect(w.find('textarea').exists()).toBe(true);
  });

  it('ADVBOX fora do ar: avisa', async () => {
    RamonFluxosAPI.opcoesAdvbox.mockRejectedValue(new Error('503'));
    const w = mount(ConfigAdvbox, { props: { config: { acao: 'tarefa' } } });
    await flushPromises();
    expect(w.find('[data-testid="advbox-indisponivel"]').exists()).toBe(true);
  });
});
