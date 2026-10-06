import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import PostPrevia from '../../components/conteudo/PostPrevia.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const imagens = ['a.jpg', 'b.jpg', 'c.jpg'];

describe('PostPrevia', () => {
  it('navega entre slides com as setas e mostra as bolinhas', async () => {
    const w = mount(PostPrevia, { props: { imagens, legenda: 'x' } });
    expect(w.find('img[data-testid="slide"]').attributes('src')).toBe('a.jpg');
    expect(w.findAll('[data-testid="bolinha"]')).toHaveLength(3);
    await w.find('[data-testid="proximo"]').trigger('click');
    expect(w.find('img[data-testid="slide"]').attributes('src')).toBe('b.jpg');
    expect(w.find('[data-testid="anterior"]').exists()).toBe(true);
  });

  it('estático não tem setas nem bolinhas', () => {
    const w = mount(PostPrevia, {
      props: { imagens: ['a.jpg'], legenda: 'x' },
    });
    expect(w.find('[data-testid="proximo"]').exists()).toBe(false);
    expect(w.findAll('[data-testid="bolinha"]')).toHaveLength(0);
  });

  it('corta a legenda em 125 caracteres com "mais" e expande', async () => {
    const w = mount(PostPrevia, {
      props: { imagens, legenda: 'a'.repeat(200) },
    });
    expect(w.find('[data-testid="legenda"]').text()).toContain('…');
    await w.find('[data-testid="legenda-mais"]').trigger('click');
    expect(w.find('[data-testid="legenda"]').text()).toContain('a'.repeat(200));
  });

  it('mostra quem será convidado como colaborador', () => {
    const w = mount(PostPrevia, {
      props: { imagens, legenda: 'x', colaboradores: ['brendantunes'] },
    });
    expect(w.find('[data-testid="colaboradores"]').text()).toBe(
      'RAMON.CONTEUDO.COLABORADORES'
    );
    const sem = mount(PostPrevia, { props: { imagens, legenda: 'x' } });
    expect(sem.find('[data-testid="colaboradores"]').exists()).toBe(false);
  });
});
