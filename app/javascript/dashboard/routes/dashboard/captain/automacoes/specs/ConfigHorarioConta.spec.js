import { mount } from '@vue/test-utils';
import ConfigHorarioConta from '../ConfigHorarioConta.vue';

const montar = config => mount(ConfigHorarioConta, { props: { config } });

describe('ConfigHorarioConta', () => {
  it('uma vez por dia: edita a hora', async () => {
    const w = montar({ tipo: 'horario_conta', hora: '08:00' });
    await w.find('[data-testid="conta-hora"]').setValue('07:30');
    expect(w.emitted('update:config').at(-1)).toEqual([
      { tipo: 'horario_conta', hora: '07:30' },
    ]);
  });

  it('trocar o modo tira a outra chave (a cada N min começa em 1; por dia volta às 08:00)', async () => {
    const w = montar({ tipo: 'horario_conta', hora: '08:00', dias: [1] });
    await w.find('[data-testid="conta-modo"]').setValue('intervalo');
    expect(w.emitted('update:config').at(-1)).toEqual([
      { tipo: 'horario_conta', dias: [1], a_cada_minutos: 1 },
    ]);
    const i = montar({ tipo: 'horario_conta', a_cada_minutos: 5 });
    expect(i.find('[data-testid="conta-minutos"]').element.value).toBe('5');
    await i.find('[data-testid="conta-modo"]').setValue('dia');
    expect(i.emitted('update:config').at(-1)).toEqual([
      { tipo: 'horario_conta', hora: '08:00' },
    ]);
  });

  it('dias: sem a chave = todos marcados; desmarcar grava a lista', async () => {
    const w = montar({ tipo: 'horario_conta', hora: '08:00' });
    await w.find('[data-testid="conta-dia-0"]').setValue(false);
    expect(w.emitted('update:config').at(-1)).toEqual([
      { tipo: 'horario_conta', hora: '08:00', dias: [1, 2, 3, 4, 5, 6] },
    ]);
  });
});
