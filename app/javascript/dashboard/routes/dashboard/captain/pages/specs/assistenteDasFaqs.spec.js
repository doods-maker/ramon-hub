import { assistenteDasFaqs } from '../assistenteDasFaqs';

describe('assistenteDasFaqs (I-FQ5)', () => {
  it('o que fala com o lead (tem caixa conectada)', () => {
    expect(
      assistenteDasFaqs([
        { id: 2, publico: 'equipe', faqs_aprovadas: 90 },
        { id: 1, publico: 'lead', faqs_aprovadas: 62 },
      ]).id
    ).toBe(1);
  });

  it('sem caixa conectada: o que tem mais FAQs aprovadas; sem nenhum, null', () => {
    expect(
      assistenteDasFaqs([
        { id: 2, publico: 'equipe', faqs_aprovadas: 0 },
        { id: 1, publico: 'equipe', faqs_aprovadas: 62 },
      ]).id
    ).toBe(1);
    expect(assistenteDasFaqs([])).toBeNull();
  });
});
