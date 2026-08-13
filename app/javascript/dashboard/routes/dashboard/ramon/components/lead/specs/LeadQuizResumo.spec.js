import { mount } from '@vue/test-utils';
import LeadQuizResumo from '../LeadQuizResumo.vue';

const mountComponent = lead =>
  mount(LeadQuizResumo, {
    props: { lead },
    global: { mocks: { $t: (k, p) => (p ? `${k} ${p.doubt}` : k) } },
  });

describe('LeadQuizResumo', () => {
  it('renders nothing without quiz data', () => {
    const wrapper = mountComponent({ custom_attributes: {} });
    expect(wrapper.find('[data-testid="lead-quiz-resumo"]').exists()).toBe(
      false
    );
  });

  it('renders answers and the qualified badge', () => {
    const wrapper = mountComponent({
      custom_attributes: {
        quiz: {
          qualificado: true,
          duvidas: ['Renda familiar'],
          respostas: [
            {
              id: 'sequela',
              pergunta: 'Sequela permanente',
              resposta: 'Sim, tenho sequela',
            },
          ],
        },
      },
    });
    const el = wrapper.find('[data-testid="lead-quiz-resumo"]');
    expect(el.exists()).toBe(true);
    expect(el.text()).toContain('Sequela permanente');
    expect(el.text()).toContain('Sim, tenho sequela');
    expect(el.text()).toContain('Renda familiar');
  });
});
