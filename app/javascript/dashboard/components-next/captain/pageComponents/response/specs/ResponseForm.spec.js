import { mount, flushPromises } from '@vue/test-utils';
import ResponseForm from '../ResponseForm.vue';

vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  const teses = [
    { id: 1, name: 'BPC/LOAS' },
    { id: 2, name: 'Trabalhista — vínculo' },
    { id: 3, name: 'Trabalhista — rescisão indireta' },
  ];
  return {
    useMapGetter: nome =>
      ref(nome === 'theses/getTheses' ? teses : { creatingItem: false }),
  };
});

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
const marcadas = wrapper =>
  wrapper
    .findAll('[data-testid="faq-tese"]')
    .filter(x => x.element.checked)
    .map(x => x.element.value);

describe('ResponseForm.vue — teses da FAQ (I-FQ1)', () => {
  it('lista as teses da conta, marca as da FAQ e manda várias', async () => {
    const wrapper = montar({
      question: 'Tenho direito?',
      answer: 'Depende.',
      geral: false,
      thesis_ids: [2],
    });
    expect(wrapper.text()).toContain('Trabalhista — rescisão indireta');
    expect(marcadas(wrapper)).toEqual(['2']);
    await wrapper.findAll('[data-testid="faq-tese"]')[2].setValue(true);
    expect(await enviar(wrapper)).toEqual({
      question: 'Tenho direito?',
      answer: 'Depende.',
      geral: false,
      thesis_ids: [2, 3],
    });
  });

  it('Geral solta as teses; nada marcado = sem tese', async () => {
    const wrapper = montar({
      question: 'Horário?',
      answer: '8h às 18h.',
      geral: false,
      thesis_ids: [1],
    });
    await wrapper.find('[data-testid="faq-geral"]').setValue(true);
    expect(await enviar(wrapper)).toMatchObject({
      geral: true,
      thesis_ids: [],
    });

    const semTese = montar({ question: 'Q?', answer: 'R.', thesis_ids: [] });
    expect(await enviar(semTese)).toMatchObject({
      geral: false,
      thesis_ids: [],
    });
  });
});
