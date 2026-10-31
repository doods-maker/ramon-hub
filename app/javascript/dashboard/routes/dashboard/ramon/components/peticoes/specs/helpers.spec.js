import { baixarTodos, formatarMB, mensagemProblema } from '../helpers';

const t = (k, v) => `${k}|${JSON.stringify(v)}`;
const TJSC = { nome: 'TJSC', limite_bytes: 11 * 1024 * 1024 };

describe('peticoes/helpers', () => {
  it('formatarMB usa vírgula', () =>
    expect(formatarMB(14.2 * 1024 * 1024)).toBe('14,2 MB'));

  it('formatarMB sem casa decimal quando é inteiro', () =>
    expect(formatarMB(11 * 1024 * 1024)).toBe('11 MB'));

  it('mensagemProblema acima_do_limite cita arquivo, tamanho e tribunal', () => {
    const arquivos = [
      { id: 12, nome: 'Laudo.pdf', tamanho: 14.2 * 1024 * 1024 },
    ];
    const texto = mensagemProblema('acima_do_limite:12', arquivos, TJSC, t);
    expect(texto).toContain('RAMON.PETICOES.PROBLEMAS.ACIMA_DO_LIMITE');
    expect(texto).toContain('Laudo.pdf');
    expect(texto).toContain('14,2 MB');
    expect(texto).toContain('TJSC');
    expect(texto).toContain('11 MB');
  });

  it('mensagemProblema sem_principal usa a chave i18n', () =>
    expect(mensagemProblema('sem_principal', [], TJSC, t)).toBe(
      'RAMON.PETICOES.PROBLEMAS.SEM_PRINCIPAL|undefined'
    ));

  it('baixarTodos clica um link por arquivo com url, 400 ms entre eles', () => {
    vi.useFakeTimers();
    const clique = vi
      .spyOn(HTMLAnchorElement.prototype, 'click')
      .mockImplementation(() => {});
    baixarTodos([
      { url: '/a', nome_numerado: '01 a.pdf' },
      { url: null, nome_numerado: '02 b.pdf' },
      { url: '/c', nome_numerado: '03 c.pdf' },
    ]);
    vi.advanceTimersByTime(0);
    expect(clique).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(400);
    expect(clique).toHaveBeenCalledTimes(2);
    clique.mockRestore();
    vi.useRealTimers();
  });
});
