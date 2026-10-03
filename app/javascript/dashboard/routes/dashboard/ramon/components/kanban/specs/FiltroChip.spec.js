import { mount } from '@vue/test-utils';
import FiltroChip from '../FiltroChip.vue';

const options = [
  { id: 1, name: 'Auxílio-acidente' },
  { id: 2, name: 'BPC' },
];
const mountChip = modelValue =>
  mount(FiltroChip, {
    props: { label: 'Tese', options, modelValue },
    global: { mocks: { $t: k => k } },
  });

describe('FiltroChip', () => {
  it('vazio: tracejado, abre a lista e escolhe', async () => {
    const wrapper = mountChip(null);
    await wrapper.find('[data-testid="filtro-chip-off"]').trigger('click');
    await wrapper.findAll('li button')[1].trigger('click');
    expect(wrapper.emitted('update:modelValue')[0]).toEqual([2]);
  });

  it('escolhido: mostra o nome e o clique limpa', async () => {
    const wrapper = mountChip(2);
    const chip = wrapper.find('[data-testid="filtro-chip-on"]');
    expect(chip.text()).toBe('Tese: BPC');
    await chip.trigger('click');
    expect(wrapper.emitted('update:modelValue')[0]).toEqual([null]);
  });
});
