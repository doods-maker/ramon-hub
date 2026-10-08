import { mount } from '@vue/test-utils';
import AssistantSystemSettingsForm from '../AssistantSystemSettingsForm.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));

const montar = publico =>
  mount(AssistantSystemSettingsForm, {
    props: { assistant: { config: { temperature: 0.3 } }, publico },
    global: { stubs: { Editor: true, Button: true } },
  });

describe('Configurações do sistema por público (I-CF4)', () => {
  it('lead vê as mensagens de transferência e encerramento', () => {
    expect(montar('lead').findAllComponents({ name: 'Editor' })).toHaveLength(
      2
    );
  });

  it('equipe (Copiloto) não vê mensagem ao cliente', () => {
    expect(montar('equipe').findAllComponents({ name: 'Editor' })).toHaveLength(
      0
    );
  });
});
