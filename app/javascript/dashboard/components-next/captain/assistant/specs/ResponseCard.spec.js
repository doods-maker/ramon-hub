import { mount } from '@vue/test-utils';
import ResponseCard from '../ResponseCard.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const montar = props =>
  mount(ResponseCard, {
    props: {
      id: 1,
      question: 'Quanto custa?',
      answer: '30% + 3',
      createdAt: 1,
      updatedAt: 1,
      ...props,
    },
    global: {
      stubs: {
        CardLayout: { template: '<div><slot /></div>' },
        Policy: true,
        DropdownMenu: true,
        Button: true,
        Checkbox: true,
        Icon: true,
      },
    },
  });

describe('ResponseCard — uso (I-FQ6)', () => {
  it('aprovada mostra quantas vezes foi usada', () => {
    expect(montar({ usos: 3 }).find('[data-testid="faq-uso"]').text()).toBe(
      'INTEL.FAQ.USADA'
    );
    expect(montar({ usos: 0 }).find('[data-testid="faq-uso"]').text()).toBe(
      'INTEL.FAQ.NUNCA_USADA'
    );
  });

  it('pendente não mostra uso', () => {
    expect(
      montar({ status: 'pending', usos: 3 })
        .find('[data-testid="faq-uso"]')
        .exists()
    ).toBe(false);
  });
});
