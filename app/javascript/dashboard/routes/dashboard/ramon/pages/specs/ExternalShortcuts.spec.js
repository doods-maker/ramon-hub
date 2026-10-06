import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import ExternalShortcuts from '../ExternalShortcuts.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const updateUISettings = vi.fn();
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: ref({}), updateUISettings }),
}));

const montar = () =>
  mount(ExternalShortcuts, {
    global: {
      mocks: { $t: key => key },
      stubs: { RamonPageHeader: true },
    },
  });

describe('ExternalShortcuts', () => {
  beforeEach(() => vi.clearAllMocks());

  it('mostra o erro de URL na própria linha, não no formulário', async () => {
    const w = montar();
    const urls = w.findAll('[data-testid="shortcut-url-input"]');
    await urls[1].setValue('site invalido');
    await urls[1].trigger('blur');
    const linhas = w.findAll('li');
    expect(linhas[1].find('[data-testid="shortcut-url-error"]').exists()).toBe(
      true
    );
    expect(w.findAll('[data-testid="shortcut-url-error"]')).toHaveLength(1);
    expect(updateUISettings).not.toHaveBeenCalled();
  });

  it('escolhe o ícone na grade e adiciona o atalho com ele', async () => {
    const w = montar();
    await w.find('[data-testid="shortcut-new-label"]').setValue('INSS');
    await w
      .find('[data-testid="shortcut-new-url"]')
      .setValue('meu.inss.gov.br');
    const icones = w.findAll('[data-testid="shortcut-new-icon"]');
    await icones[8].trigger('click');
    expect(icones[8].attributes('aria-checked')).toBe('true');
    await w.find('[data-testid="shortcut-add"]').trigger('click');
    const salvos = updateUISettings.mock.calls[0][0].external_shortcuts;
    expect(salvos.at(-1)).toEqual({
      label: 'INSS',
      url: 'https://meu.inss.gov.br',
      icon: 'i-lucide-landmark',
    });
  });
});
