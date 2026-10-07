import { mount, flushPromises } from '@vue/test-utils';
import DocumentForm from '../DocumentForm.vue';

// objeto simples (não ref): o form só lê uiFlags.value.creatingItem
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { creatingItem: false } }),
}));

const montar = () => mount(DocumentForm, { props: { assistantId: 1 } });
const enviar = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
};

describe('DocumentForm.vue', () => {
  it('colar texto: manda título e texto, sem link', async () => {
    const wrapper = montar();
    await wrapper.find('[data-testid="documento-modo-texto"]').trigger('click');
    await wrapper.findAll('input')[0].setValue('Honorários');
    await wrapper
      .find('textarea')
      .setValue('O honorário é 30% dos atrasados + 3 benefícios.');
    await enviar(wrapper);

    const [dados] = wrapper.emitted('submit')[0];
    expect(dados.get('document[name]')).toBe('Honorários');
    expect(dados.get('document[content]')).toContain('30%');
    expect(dados.get('document[external_link]')).toBeNull();
    expect(dados.get('document[assistant_id]')).toBe('1');
  });

  it('colar texto sem título ou sem texto não envia', async () => {
    const wrapper = montar();
    await wrapper.find('[data-testid="documento-modo-texto"]').trigger('click');
    await wrapper.find('textarea').setValue('só o texto');
    await enviar(wrapper);
    expect(wrapper.emitted('submit')).toBeUndefined();
  });

  it('link continua igual: usa o link como nome quando o nome fica vazio', async () => {
    const wrapper = montar();
    await wrapper
      .findAll('input')[0]
      .setValue('https://ramonantonio.adv.br/bpc');
    await enviar(wrapper);

    const [dados] = wrapper.emitted('submit')[0];
    expect(dados.get('document[external_link]')).toBe(
      'https://ramonantonio.adv.br/bpc'
    );
    expect(dados.get('document[name]')).toBe('https://ramonantonio.adv.br/bpc');
    expect(dados.get('document[content]')).toBeNull();
  });
});
