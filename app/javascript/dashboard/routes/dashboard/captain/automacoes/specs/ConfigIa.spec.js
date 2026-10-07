import { mount, flushPromises } from '@vue/test-utils';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import CaptainScenariosAPI from 'dashboard/api/captain/scenarios';
import ConfigIa from '../ConfigIa.vue';

vi.mock('dashboard/api/captain/assistant', () => ({
  default: { get: vi.fn() },
}));
vi.mock('dashboard/api/captain/scenarios', () => ({
  default: { get: vi.fn() },
}));

const montar = (tipo, config = {}) =>
  mount(ConfigIa, { props: { tipo, config } });

describe('ConfigIa', () => {
  it('perguntar_ia edita a pergunta e não chama o Captain', async () => {
    const w = montar('perguntar_ia', {});
    await w.find('textarea').setValue('Mandou o CNIS?');
    expect(w.emitted('update:config').at(-1)).toEqual([
      { pergunta: 'Mandou o CNIS?' },
    ]);
    expect(CaptainAssistantAPI.get).not.toHaveBeenCalled();
  });

  it('rodar_skill lista assistentes e skills; trocar o assistente limpa a skill', async () => {
    CaptainAssistantAPI.get.mockResolvedValue({
      data: {
        payload: [
          { id: 1, name: 'Atendente' },
          { id: 2, name: 'Analista' },
        ],
      },
    });
    CaptainScenariosAPI.get.mockResolvedValue({
      data: { payload: [{ id: 5, title: 'Resumo do caso', enabled: true }] },
    });
    const w = montar('rodar_skill', { assistente_id: 1, skill_id: 5 });
    await flushPromises();
    expect(CaptainScenariosAPI.get).toHaveBeenCalledWith({ assistantId: 1 });
    expect(w.find('[data-testid="ia-skill"]').text()).toContain(
      'Resumo do caso'
    );
    await w.find('[data-testid="ia-assistente"]').setValue('2');
    expect(w.emitted('update:config').at(-1)).toEqual([
      { assistente_id: 2, skill_id: null },
    ]);
  });

  it('resposta velha de skills não sobrescreve a nova', async () => {
    CaptainAssistantAPI.get.mockResolvedValue({
      data: {
        payload: [
          { id: 1, name: 'A' },
          { id: 2, name: 'B' },
        ],
      },
    });
    let soltaA;
    CaptainScenariosAPI.get
      .mockImplementationOnce(
        () =>
          new Promise(r => {
            soltaA = r;
          })
      )
      .mockResolvedValueOnce({
        data: { payload: [{ id: 9, title: 'Skill B', enabled: true }] },
      });
    const w = montar('rodar_skill', { assistente_id: 1 });
    await flushPromises();
    await w.find('[data-testid="ia-assistente"]').setValue('2');
    await flushPromises();
    soltaA({ data: { payload: [{ id: 8, title: 'Skill A', enabled: true }] } });
    await flushPromises();
    const txt = w.find('[data-testid="ia-skill"]').text();
    expect(txt).toContain('Skill B');
    expect(txt).not.toContain('Skill A');
  });

  it('rodar_skill não oferece skill desligada', async () => {
    CaptainAssistantAPI.get.mockResolvedValue({
      data: { payload: [{ id: 1, name: 'Atendente' }] },
    });
    CaptainScenariosAPI.get.mockResolvedValue({
      data: {
        payload: [
          { id: 5, title: 'Ligada', enabled: true },
          { id: 6, title: 'Desligada', enabled: false },
        ],
      },
    });
    const w = montar('rodar_skill', { assistente_id: 1 });
    await flushPromises();
    const txt = w.find('[data-testid="ia-skill"]').text();
    expect(txt).toContain('Ligada');
    expect(txt).not.toContain('Desligada');
  });

  it('sem Captain (FOSS): avisa e não quebra', async () => {
    CaptainAssistantAPI.get.mockRejectedValue(new Error('404'));
    const w = montar('rodar_skill', {});
    await flushPromises();
    expect(w.find('[data-testid="ia-sem-captain"]').exists()).toBe(true);
  });
});
