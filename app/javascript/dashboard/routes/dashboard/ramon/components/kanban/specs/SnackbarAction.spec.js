import { mount } from '@vue/test-utils';
import Snackbar from 'dashboard/components/Snackbar.vue';

describe('Snackbar.vue — action de botão', () => {
  it('renderiza botão quando action.type é button e chama onClick', async () => {
    const onClick = vi.fn();
    const wrapper = mount(Snackbar, {
      props: {
        message: 'Etapa alterada',
        action: { type: 'button', message: 'Desfazer', onClick },
      },
    });
    const button = wrapper.find('[data-testid="snackbar-action-button"]');
    expect(button.exists()).toBe(true);
    expect(button.text()).toBe('Desfazer');
    await button.trigger('click');
    expect(onClick).toHaveBeenCalledTimes(1);
  });

  it('não renderiza botão para action de link', () => {
    const wrapper = mount(Snackbar, {
      props: {
        message: 'msg',
        action: { type: 'link', to: '/x', message: 'ver' },
      },
      global: { stubs: { RouterLink: true } },
    });
    expect(
      wrapper.find('[data-testid="snackbar-action-button"]').exists()
    ).toBe(false);
  });
});
