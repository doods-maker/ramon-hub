import { mount } from '@vue/test-utils';
import Paleta from '../Paleta.vue';

describe('Paleta', () => {
  it('no Horário da conta só os passos que rodam sem lead', () => {
    const w = mount(Paleta, { props: { alvo: 'conta' } });
    expect(
      w
        .findAll('[data-testid^="paleta-"]')
        .map(b => b.attributes('data-testid'))
    ).toEqual([
      'paleta-se',
      'paleta-escolha',
      'paleta-rotina',
      'paleta-avisar_push',
      'paleta-esperar',
      'paleta-parar',
    ]);
  });
});
