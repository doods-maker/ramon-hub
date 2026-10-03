import { setActivePinia, createPinia } from 'pinia';
import { useChegadasStore } from './chegadas';
import ChegadasAPI from 'dashboard/api/ramonChegadas';

vi.mock('dashboard/api/ramonChegadas', () => ({
  default: { get: vi.fn(), create: vi.fn(), responder: vi.fn() },
}));

const chegada = (over = {}) => ({
  id: 1,
  cliente_nome: 'Maria',
  estado: 'aguardando',
  criado_por: { id: 10, name: 'Gabriela' },
  destinatario: { id: 20, name: 'Brenda' },
  ...over,
});

describe('useChegadasStore', () => {
  beforeEach(() => {
    localStorage.clear();
    setActivePinia(createPinia());
  });

  it('alerta o destinatário enquanto não responde', () => {
    const store = useChegadasStore();
    store.upsert(chegada());
    expect(store.alertasPara(20)).toHaveLength(1);
    expect(store.alertasPara(10)).toHaveLength(0);
    store.upsert(chegada({ estado: 'respondido' }));
    expect(store.alertasPara(20)).toHaveLength(0);
  });

  it('escalada alerta quem avisou até marcar visto; resposta tardia apaga', () => {
    const store = useChegadasStore();
    store.upsert(chegada({ estado: 'escalado' }));
    expect(store.alertasPara(10)).toHaveLength(1);
    store.marcarVisto(1);
    expect(store.alertasPara(10)).toHaveLength(0);
    store.upsert(chegada({ id: 2, estado: 'escalado' }));
    store.upsert(chegada({ id: 2, estado: 'respondido' }));
    expect(store.alertasPara(10)).toHaveLength(0);
  });

  it('vistos sobrevivem a recarregar a página', () => {
    useChegadasStore().marcarVisto(1);
    setActivePinia(createPinia());
    const store = useChegadasStore();
    store.upsert(chegada({ estado: 'escalado' }));
    expect(store.alertasPara(10)).toHaveLength(0);
  });

  it('carregar recupera pendências após recarregar a página', async () => {
    ChegadasAPI.get.mockResolvedValue({
      data: { payload: [chegada()], pode_avisar: true },
    });
    const store = useChegadasStore();
    await store.carregar();
    expect(store.podeAvisar).toBe(true);
    expect(store.alertasPara(20)).toHaveLength(1);
  });
});
