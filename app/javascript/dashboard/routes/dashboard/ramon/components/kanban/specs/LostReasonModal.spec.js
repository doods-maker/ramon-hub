import { mount } from '@vue/test-utils';
import LostReasonModal from '../LostReasonModal.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => (key === 'RAMON.FUNIL.LOST.OTHER' ? 'Outro' : key),
  }),
}));

const REASONS = [
  { id: 1, name: 'Honorário' },
  { id: 2, name: 'Sem retorno' },
];

const mountModal = (lostReasons = REASONS) =>
  mount(LostReasonModal, {
    props: { lostReasons },
    global: { mocks: { $t: k => k }, stubs: { RouterLink: true } },
  });

const confirmBtn = wrapper =>
  wrapper.find('[data-testid="lost-reason-confirm"]');

describe('LostReasonModal.vue', () => {
  it('sem motivo escolhido não confirma', async () => {
    const wrapper = mountModal();
    expect(confirmBtn(wrapper).attributes('disabled')).toBeDefined();
    await confirmBtn(wrapper).trigger('click');
    expect(wrapper.emitted('confirmMove')).toBeFalsy();
  });

  it('confirma com o motivo da lista e o detalhe opcional', async () => {
    const wrapper = mountModal();
    await wrapper.find('[data-testid="lost-reason-select"]').setValue(1);
    await confirmBtn(wrapper).trigger('click');
    await wrapper.find('[data-testid="lost-reason-detail"]').setValue('caro');
    await confirmBtn(wrapper).trigger('click');
    expect(wrapper.emitted('confirmMove')).toEqual([
      [{ lostReason: 'Honorário' }],
      [{ lostReason: 'Honorário — caro' }],
    ]);
  });

  it('"Outro" exige o texto livre', async () => {
    const wrapper = mountModal();
    await wrapper.find('[data-testid="lost-reason-select"]').setValue('outro');
    expect(confirmBtn(wrapper).attributes('disabled')).toBeDefined();
    await wrapper
      .find('[data-testid="lost-reason-detail"]')
      .setValue('mudou de cidade');
    await confirmBtn(wrapper).trigger('click');
    expect(wrapper.emitted('confirmMove')).toEqual([
      [{ lostReason: 'Outro — mudou de cidade' }],
    ]);
  });

  it('sem motivos cadastrados ainda dá para usar o "Outro"', async () => {
    const wrapper = mountModal([]);
    expect(wrapper.find('[data-testid="lost-no-reasons"]').exists()).toBe(true);
    await wrapper.find('[data-testid="lost-reason-select"]').setValue('outro');
    await wrapper.find('[data-testid="lost-reason-detail"]').setValue('x');
    await confirmBtn(wrapper).trigger('click');
    expect(wrapper.emitted('confirmMove')).toEqual([
      [{ lostReason: 'Outro — x' }],
    ]);
  });

  it('Cancelar emite cancelMove', async () => {
    const wrapper = mountModal();
    await wrapper.find('button').trigger('click');
    expect(wrapper.emitted('cancelMove')).toBeTruthy();
  });
});
