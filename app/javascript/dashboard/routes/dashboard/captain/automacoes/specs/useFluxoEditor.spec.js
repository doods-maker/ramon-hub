import { effectScope, nextTick } from 'vue';
import { flushPromises } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import { useFluxoEditor } from '../useFluxoEditor';

vi.mock('dashboard/api/ramonFluxos', () => ({
  default: {
    show: vi.fn(),
    update: vi.fn(),
    publicar: vi.fn(),
    ensaio: vi.fn(),
    rodar: vi.fn(),
  },
}));

const RASCUNHO = {
  nos: [
    {
      id: 'n1',
      tipo: 'gatilho',
      config: { tipo: 'manual' },
      posicao: { x: 0, y: 0 },
    },
    {
      id: 'n2',
      tipo: 'nota_privada',
      config: { texto: 'oi' },
      posicao: { x: 0, y: 140 },
    },
  ],
  setas: [{ de: 'n1', saida: 's', para: 'n2' }],
};
const comTexto = (nodes, texto) =>
  nodes.map(n =>
    n.id === 'n2' ? { ...n, data: { ...n.data, config: { texto } } } : n
  );

describe('useFluxoEditor', () => {
  beforeEach(() => {
    // só setTimeout: o flushPromises usa setImmediate
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    RamonFluxosAPI.show.mockResolvedValue({
      data: { id: 7, nome: 'F', versao: null, versoes: [], rascunho: RASCUNHO },
    });
    RamonFluxosAPI.update.mockResolvedValue({ data: { id: 7 } });
    RamonFluxosAPI.publicar.mockResolvedValue({ data: { versao: 1 } });
    RamonFluxosAPI.ensaio.mockResolvedValue({ data: { id: 99 } });
  });
  afterEach(() => vi.useRealTimers());

  it('carrega sem ficar sujo', async () => {
    const ed = useFluxoEditor();
    await ed.carregar(7);
    expect(ed.nodes.value).toHaveLength(2);
    expect(ed.edges.value).toHaveLength(1);
    expect(ed.sujo.value).toBe(false);
  });

  it('fluxo do sistema não fica sujo nem salva sozinho', async () => {
    RamonFluxosAPI.show.mockResolvedValue({
      data: { id: 7, origem: 'sistema', versoes: [], rascunho: RASCUNHO },
    });
    const ed = useFluxoEditor();
    await ed.carregar(7);
    ed.nodes.value = comTexto(ed.nodes.value, 'novo');
    await nextTick();
    vi.advanceTimersByTime(1000);
    await flushPromises();
    expect(ed.sujo.value).toBe(false);
    expect(RamonFluxosAPI.update).not.toHaveBeenCalled();
  });

  it('salva o rascunho 1 s depois da última mudança', async () => {
    const ed = useFluxoEditor();
    await ed.carregar(7);
    ed.nodes.value = comTexto(ed.nodes.value, 'novo');
    await nextTick();
    vi.advanceTimersByTime(999);
    expect(RamonFluxosAPI.update).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    await flushPromises();
    expect(RamonFluxosAPI.update).toHaveBeenCalledTimes(1);
    expect(
      RamonFluxosAPI.update.mock.calls[0][1].rascunho.nos[1].config
    ).toEqual({ texto: 'novo' });
    expect(ed.sujo.value).toBe(false);
  });

  it('sair da tela (fim do escopo) cancela o autosave pendente', async () => {
    const escopo = effectScope();
    const ed = escopo.run(() => useFluxoEditor());
    await ed.carregar(7);
    ed.nodes.value = comTexto(ed.nodes.value, 'novo');
    await nextTick();
    escopo.stop();
    vi.advanceTimersByTime(1000);
    await flushPromises();
    expect(RamonFluxosAPI.update).not.toHaveBeenCalled();
  });

  it('publicar salva a mudança pendente ANTES de publicar', async () => {
    const ed = useFluxoEditor();
    await ed.carregar(7);
    ed.nodes.value = comTexto(ed.nodes.value, 'antes de publicar');
    await nextTick();
    expect(await ed.publicar()).toBe(1);
    expect(RamonFluxosAPI.update.mock.invocationCallOrder[0]).toBeLessThan(
      RamonFluxosAPI.publicar.mock.invocationCallOrder[0]
    );
  });

  it('save em voo não corre contra publicar: um único update, antes do publicar', async () => {
    let solta;
    RamonFluxosAPI.update.mockImplementationOnce(
      () =>
        new Promise(r => {
          solta = () => r({ data: { id: 7 } });
        })
    );
    const ed = useFluxoEditor();
    await ed.carregar(7);
    ed.nodes.value = comTexto(ed.nodes.value, 'em voo');
    await nextTick();
    vi.advanceTimersByTime(1000); // autosave dispara e fica pendente
    await flushPromises();
    expect(RamonFluxosAPI.update).toHaveBeenCalledTimes(1);
    const p = ed.publicar();
    await flushPromises();
    expect(RamonFluxosAPI.publicar).not.toHaveBeenCalled();
    solta();
    expect(await p).toBe(1);
    expect(RamonFluxosAPI.update).toHaveBeenCalledTimes(1);
  });

  it('desenho inválido não chama o back e acende o passo', async () => {
    const ed = useFluxoEditor();
    await ed.carregar(7);
    ed.nodes.value = comTexto(ed.nodes.value, '');
    await nextTick();
    expect(await ed.publicar()).toBeNull();
    expect(RamonFluxosAPI.publicar).not.toHaveBeenCalled();
    expect(ed.mostrarErros.value).toBe(true);
    expect(ed.nosComErro.value.has('n2')).toBe(true);
  });

  it('erro 422 do back: passo apontado acende, o resto vai para a faixa', async () => {
    RamonFluxosAPI.publicar.mockRejectedValue({
      response: {
        status: 422,
        data: {
          erros: [
            'Passo n2: falta texto',
            'O fluxo não pode voltar para um passo anterior',
          ],
        },
      },
    });
    const ed = useFluxoEditor();
    await ed.carregar(7);
    expect(await ed.publicar()).toBeNull();
    expect(ed.errosServidor.value).toHaveLength(2);
    expect(ed.nosComErro.value.has('n2')).toBe(true);
  });

  it('ensaiar salva antes e devolve a execução', async () => {
    const ed = useFluxoEditor();
    await ed.carregar(7);
    ed.nodes.value = comTexto(ed.nodes.value, 'ensaio');
    await nextTick();
    const exec = await ed.ensaiar({ lead_id: 5 });
    expect(exec).toEqual({ id: 99 });
    expect(RamonFluxosAPI.ensaio).toHaveBeenCalledWith(7, {
      lead_id: 5,
      usar: 'rascunho',
    });
    expect(RamonFluxosAPI.update).toHaveBeenCalled();
  });
});
