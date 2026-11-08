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

  // Teste ponta a ponta de 07/11: o padrão é ir para Documentos (o assistente assume), sem motivo.
  it('tese que passa por Documentos: por padrão vai para Documentos, sem motivo', async () => {
    const wrapper = montar({ pedeMotivo: true });
    expect(
      wrapper.find('[data-testid="motivo-pula-documentos"]').exists()
    ).toBe(false);
    await wrapper.find('[data-testid="won-value-skip"]').trigger('click');
    expect(wrapper.emitted('confirmValue')[0]).toEqual([
      { value: null, paraDocumentos: true },
    ]);
  });

  it('ficar na coluna escolhida exige o motivo, que vai junto', async () => {
    const wrapper = montar({ pedeMotivo: true });
    const salvar = () => wrapper.find('[data-testid="won-value-save"]');
    const pular = () => wrapper.find('[data-testid="won-value-skip"]');
    await wrapper.find('[data-testid="pula-documentos-ficar"]').setValue(true);
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
