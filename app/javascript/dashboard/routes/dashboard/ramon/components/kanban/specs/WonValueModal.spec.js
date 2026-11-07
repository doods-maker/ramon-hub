import { mount } from '@vue/test-utils';
import WonValueModal from '../WonValueModal.vue';

const montar = props =>
  mount(WonValueModal, { props, global: { mocks: { $t: k => k } } });

describe('WonValueModal.vue', () => {
  it('sem pedir motivo, não mostra o campo e confirma como hoje', async () => {
    const wrapper = montar({});
    expect(
      wrapper.find('[data-testid="motivo-pula-documentos"]').exists()
    ).toBe(false);
    await wrapper.find('[data-testid="won-value-skip"]').trigger('click');
    expect(wrapper.emitted('confirmValue')[0]).toEqual([{ value: null }]);
  });

  it('pulando Documentos, o motivo é obrigatório e vai junto', async () => {
    const wrapper = montar({ pedeMotivo: true });
    const salvar = () => wrapper.find('[data-testid="won-value-save"]');
    const pular = () => wrapper.find('[data-testid="won-value-skip"]');
    expect(salvar().attributes('disabled')).toBeDefined();
    expect(pular().attributes('disabled')).toBeDefined();

    await wrapper.find('[data-testid="motivo-pula-documentos"]').setValue('  ');
    expect(salvar().attributes('disabled')).toBeDefined();

    await wrapper
      .find('[data-testid="motivo-pula-documentos"]')
      .setValue(' Cliente já trouxe tudo ');
    await pular().trigger('click');
    expect(wrapper.emitted('confirmValue')[0]).toEqual([
      { value: null, motivo: 'Cliente já trouxe tudo' },
    ]);
  });
});
