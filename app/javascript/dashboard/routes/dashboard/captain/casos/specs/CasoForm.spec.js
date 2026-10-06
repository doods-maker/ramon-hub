import { mount } from '@vue/test-utils';
import CasoForm from '../CasoForm.vue';

describe('Formulário do caso de teste', () => {
  it('não salva se a última fala não for da pessoa', async () => {
    const wrapper = mount(CasoForm, {
      props: {
        caso: {
          id: 1,
          titulo: 'A1',
          mensagens: [
            { role: 'user', content: 'oi' },
            { role: 'assistant', content: 'olá' },
          ],
          criterios: {},
        },
      },
    });

    await wrapper.find('[data-testid="caso-salvar"]').trigger('click');

    expect(wrapper.find('[data-testid="caso-form-erro"]').exists()).toBe(true);
    expect(wrapper.emitted('salvar')).toBeUndefined();
  });

  it('monta o payload com falas e critérios em lista', async () => {
    const wrapper = mount(CasoForm);

    await wrapper.find('[data-testid="caso-titulo"]').setValue(' A11 ');
    await wrapper
      .find('[data-testid="caso-fala-texto"]')
      .setValue('quero falar com o Dr. Ramon');
    await wrapper
      .find('[data-testid="caso-deve-usar"]')
      .setValue('handoff, faq_lookup,');
    await wrapper.find('[data-testid="caso-handoff"]').setValue('sim');
    await wrapper.find('[data-testid="caso-salvar"]').trigger('click');

    expect(wrapper.emitted('salvar')[0][0]).toEqual({
      titulo: 'A11',
      grupo: '',
      ativo: true,
      mensagens: [{ role: 'user', content: 'quero falar com o Dr. Ramon' }],
      criterios: {
        deve_usar: ['handoff', 'faq_lookup'],
        nao_deve_usar: [],
        handoff: 'sim',
        deve_conter: [],
        nao_pode_conter: [],
        rubrica: '',
      },
    });
  });

  it('caso existente mostra excluir e traz os critérios', () => {
    const wrapper = mount(CasoForm, {
      props: {
        caso: {
          id: 3,
          titulo: 'A5',
          mensagens: [{ role: 'user', content: 'quanto cobram?' }],
          criterios: { deve_usar: ['faq_lookup'], handoff: 'nao' },
        },
      },
    });

    expect(wrapper.find('[data-testid="caso-excluir"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="caso-deve-usar"]').element.value).toBe(
      'faq_lookup'
    );
  });
});
