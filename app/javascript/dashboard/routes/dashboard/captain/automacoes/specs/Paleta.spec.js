import { mount } from '@vue/test-utils';
import Paleta from '../Paleta.vue';

const SEM_LEAD = [
  'paleta-se',
  'paleta-escolha',
  'paleta-rotina',
  'paleta-avisar_push',
  'paleta-esperar',
  'paleta-parar',
];
const itens = alvo =>
  mount(Paleta, { props: { alvo } })
    .findAll('[data-testid^="paleta-"]')
    .map(b => b.attributes('data-testid'));

describe('Paleta', () => {
  it('nos gatilhos de fora do funil (alvo outro) também só os passos sem lead', () => {
    expect(itens('outro')).toEqual(SEM_LEAD);
    expect(itens('lead')).toContain('paleta-avisar_sino');
  });

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
