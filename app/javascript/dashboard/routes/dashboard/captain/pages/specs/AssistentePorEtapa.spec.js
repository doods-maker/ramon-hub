import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import AssistentePorEtapa from '../comoIaAtende/AssistentePorEtapa.vue';

// Veio da Configuração do Funil (Inteligência num lugar só, 2026-11-22).
vi.mock('dashboard/api/captain/assistant', () => ({
  default: { get: vi.fn(() => Promise.reject(new Error('sem Captain'))) },
}));

const montar = ({
  updateStage = vi.fn(),
  stages = [],
  etapaDocumentos = true,
} = {}) => {
  const store = createStore({
    modules: {
      leadConfig: {
        namespaced: true,
        getters: {
          getStages: () => stages,
          getEtapaDocumentos: () => etapaDocumentos,
        },
        actions: { updateStage, get: vi.fn() },
      },
    },
  });
  return mount(AssistentePorEtapa, {
    global: { plugins: [store], mocks: { $t: k => k } },
  });
};

it('etapa de ganho escolhe o assistente da etapa (vazio = o da caixa)', async () => {
  CaptainAssistantAPI.get.mockResolvedValueOnce({
    data: { payload: [{ id: 5, name: 'Documentos' }] },
  });
  const updateStage = vi.fn().mockResolvedValue({});
  const wrapper = montar({
    updateStage,
    stages: [
      { id: 1, name: 'Novo' },
      { id: 3, name: 'Documentos', is_won: true, captain_assistant_id: null },
      { id: 4, name: 'Jurídico', is_won: true, captain_assistant_id: 5 },
    ],
  });
  await flushPromises();
  const selects = wrapper.findAll('[data-testid="stage-assistente"]');
  expect(selects).toHaveLength(2);

  await selects[0].setValue('5');
  expect(updateStage).toHaveBeenLastCalledWith(expect.anything(), {
    id: 3,
    captain_assistant_id: 5,
  });
  await selects[1].setValue('');
  expect(updateStage).toHaveBeenLastCalledWith(expect.anything(), {
    id: 4,
    captain_assistant_id: null,
  });
});

it('sem assistentes (sem o Captain), o bloco nem aparece', async () => {
  const wrapper = montar({
    stages: [{ id: 3, name: 'Documentos', is_won: true }],
  });
  await flushPromises();
  expect(wrapper.find('[data-testid="assistente-por-etapa"]').exists()).toBe(
    false
  );
});

it('chave da etapa Documentos desligada: o bloco nem aparece', async () => {
  CaptainAssistantAPI.get.mockResolvedValueOnce({
    data: { payload: [{ id: 5, name: 'Documentos' }] },
  });
  const wrapper = montar({
    etapaDocumentos: false,
    stages: [{ id: 3, name: 'Documentos', is_won: true }],
  });
  await flushPromises();
  expect(wrapper.find('[data-testid="assistente-por-etapa"]').exists()).toBe(
    false
  );
});
