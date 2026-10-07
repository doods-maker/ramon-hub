import { mount, flushPromises } from '@vue/test-utils';
import ResponseForm from '../ResponseForm.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { creatingItem: false } }),
}));

const montar = response =>
  mount(ResponseForm, {
    props: { mode: 'edit', response },
    global: { stubs: { Editor: true } },
  });
const enviar = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  return wrapper.emitted('submit')[0][0];
};

describe('ResponseForm.vue — tese (I-FQ1)', () => {
  it('mostra a tese da FAQ e manda nulo quando vira "Sem tese"', async () => {
    const wrapper = montar({
      question: 'O que é o BPC?',
      answer: 'Benefício assistencial.',
      tese: 'bpc-loas',
    });
    const campo = wrapper.find('[data-testid="faq-tese"]');
    expect(campo.element.value).toBe('bpc-loas');
    await campo.setValue('');
    expect(await enviar(wrapper)).toEqual({
      question: 'O que é o BPC?',
      answer: 'Benefício assistencial.',
      tese: null,
    });
  });

  it('FAQ sem tese pode ganhar uma', async () => {
    const wrapper = montar({
      question: 'Horário?',
      answer: '8h às 18h.',
      tese: null,
    });
    await wrapper.find('[data-testid="faq-tese"]').setValue('geral');
    expect((await enviar(wrapper)).tese).toBe('geral');
  });
});
