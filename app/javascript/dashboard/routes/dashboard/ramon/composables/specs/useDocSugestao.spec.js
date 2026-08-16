import { ref } from 'vue';
import { useDocSugestao } from '../useDocSugestao';

const dispatch = vi.fn().mockResolvedValue();
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: (...args) => dispatch(...args) }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

describe('useDocSugestao', () => {
  beforeEach(() => dispatch.mockClear());

  it('aceitar grava resolvida + recebido + anexo vinculado (merge só das chaves)', async () => {
    const { resolver } = useDocSugestao(ref({ id: 7 }));
    await resolver(true, { itemId: 3, attachmentId: 99 });
    expect(dispatch).toHaveBeenCalledWith('leads/update', {
      id: 7,
      custom_attributes: {
        doc_sugestao: { resolvida: true },
        doc_status: { 3: 'recebido' },
        doc_anexos: { 3: 99 },
      },
    });
  });

  it('dispensar grava só resolvida', async () => {
    const { resolver } = useDocSugestao(ref({ id: 7 }));
    await resolver(false, { itemId: 3, attachmentId: 99 });
    expect(dispatch).toHaveBeenCalledWith('leads/update', {
      id: 7,
      custom_attributes: { doc_sugestao: { resolvida: true } },
    });
  });

  it('guard: segunda chamada em voo é ignorada', async () => {
    let release;
    // eslint-disable-next-line no-return-assign, no-promise-executor-return
    dispatch.mockReturnValueOnce(new Promise(r => (release = r)));
    const { resolver } = useDocSugestao(ref({ id: 7 }));
    const first = resolver(true, { itemId: 3, attachmentId: 99 });
    resolver(false, { itemId: 3, attachmentId: 99 });
    release();
    await first;
    expect(dispatch).toHaveBeenCalledTimes(1);
  });
});
