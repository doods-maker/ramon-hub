import { mount } from '@vue/test-utils';
import RamonEvent from '../RamonEvent.vue';
import { provideMessageContext } from '../../provider.js';
import { emitter } from 'shared/helpers/mitt';
import { useAlert } from 'dashboard/composables';

vi.mock('shared/helpers/mitt', () => ({ emitter: { emit: vi.fn() } }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => {
    if (key === 'getSelectedChat') return { value: { id: 1 } };
    if (key === 'leads/getLeadByConversationId')
      return { value: () => undefined };
    return { value: [] };
  },
}));
vi.mock('dashboard/routes/dashboard/ramon/composables/useDocSugestao', () => ({
  useDocSugestao: () => ({ pending: { value: false }, resolver: vi.fn() }),
}));

const mountRamonEvent = contentAttributes =>
  mount(
    {
      components: { RamonEvent },
      setup() {
        provideMessageContext({
          content: 'Um evento do coach',
          contentAttributes: { value: contentAttributes },
        });
      },
      template: '<RamonEvent />',
    },
    {
      global: { mocks: { $t: key => key } },
    }
  );

describe('RamonEvent', () => {
  it('renderiza as opções do coach com título, texto e botão usar', () => {
    const wrapper = mountRamonEvent({
      ramonEvent: 'coach',
      objecao: 'preco',
      opcoes: [
        { titulo: 'Empatia', texto: 'Entendo a preocupação...' },
        { titulo: 'Prova social', texto: 'Já ajudamos centenas de casos...' },
      ],
    });

    const botoes = wrapper.findAll('[data-testid="coach-usar"]');
    expect(botoes).toHaveLength(2);
    expect(botoes[0].text()).toContain('Empatia');
    expect(botoes[0].text()).toContain('Entendo a preocupação...');
  });

  it('clicar em usar emite insertIntoNormalEditor com o texto e mostra alerta', async () => {
    const wrapper = mountRamonEvent({
      ramonEvent: 'coach',
      objecao: 'preco',
      opcoes: [{ titulo: 'Empatia', texto: 'Entendo a preocupação...' }],
    });

    await wrapper.find('[data-testid="coach-usar"]').trigger('click');

    expect(emitter.emit).toHaveBeenCalledWith(
      'insertIntoNormalEditor',
      'Entendo a preocupação...'
    );
    expect(useAlert).toHaveBeenCalledWith('RAMON.COACH.USADO');
  });

  it('evento não-coach (doc_match) não renderiza opções', () => {
    const wrapper = mountRamonEvent({
      ramonEvent: 'doc_match',
      itemId: 3,
      attachmentId: 99,
    });

    expect(wrapper.find('[data-testid="coach-usar"]').exists()).toBe(false);
  });
});
