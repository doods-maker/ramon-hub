import { mount, flushPromises } from '@vue/test-utils';
import AssistantBasicSettingsForm from '../AssistantBasicSettingsForm.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const ASSISTENTE = {
  name: 'Atendimento',
  description: 'Fala com o lead',
  config: { feature_memory: false, feature_citation: true },
};
const montar = (publico, assistant = ASSISTENTE) =>
  mount(AssistantBasicSettingsForm, {
    props: { assistant, publico },
    global: {
      stubs: {
        Input: true,
        Editor: true,
        Switch: true,
        Button: {
          emits: ['click'],
          template: '<button data-testid="salvar" @click="clicar" />',
          methods: {
            clicar() {
              this.$emit('click');
            },
          },
        },
      },
    },
  });

describe('Configurações básicas por público (I-CF3, I-CF4, I-X7)', () => {
  it('lead: 3 chaves (FAQ de conversa, memória, contato), sem citação', () => {
    const chaves = montar('lead').findAll('[data-testid="config-chave"]');
    expect(chaves.map(c => c.text())).toEqual([
      'CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CONVERSATION_FAQS',
      expect.stringContaining(
        'CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_MEMORIES'
      ),
      'CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CONTACT_ATTRIBUTES',
    ]);
  });

  it('equipe: nenhuma chave, só o aviso', () => {
    const wrapper = montar('equipe');
    expect(wrapper.findAll('[data-testid="config-chave"]')).toHaveLength(0);
    expect(wrapper.text()).toContain('INTEL.CONFIG.SO_EQUIPE');
  });

  it('nome do escritório pré-preenchido; salva citação desligada', async () => {
    const wrapper = montar('lead');
    await wrapper.find('[data-testid="salvar"]').trigger('click');
    await flushPromises();
    const { config } = wrapper.emitted('submit')[0][0];
    expect(config).toMatchObject({
      product_name: 'Ramon Antonio Advogados',
      feature_citation: false,
    });
  });
});
