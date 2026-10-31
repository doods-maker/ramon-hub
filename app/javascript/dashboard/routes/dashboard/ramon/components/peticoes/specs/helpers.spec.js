import {
  baixarTodos,
  erroPeticao,
  formatarMB,
  mensagemProblema,
} from '../helpers';

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

  it('baixarTodos busca cada arquivo com url, em ordem, e salva com o nome numerado', async () => {
    URL.createObjectURL = vi.fn(() => 'blob:x');
    URL.revokeObjectURL = vi.fn();
    const nomes = [];
    const clique = vi
      .spyOn(HTMLAnchorElement.prototype, 'click')
      .mockImplementation(function registrar() {
        nomes.push(this.download);
      });
    const buscar = vi.fn(async a => new Blob([a.url]));
    await baixarTodos(
      [
        { url: '/a', nome_numerado: '01 a.pdf' },
        { url: null, nome_numerado: '02 b.pdf' },
        { url: '/c', nome_numerado: '03 c.pdf' },
      ],
      buscar
    );
    expect(buscar.mock.calls.map(([a]) => a.url)).toEqual(['/a', '/c']);
    expect(nomes).toEqual(['01 a.pdf', '03 c.pdf']);
    clique.mockRestore();
  });

  it('erroPeticao traduz os códigos do backend e cai na mensagem do servidor', () => {
    const erro = data => ({ response: { data } });
    expect(erroPeticao(erro({ error: 'SO_RESPONSAVEL' }), t)).toBe(
      'RAMON.PETICOES.ERROS.SO_RESPONSAVEL|undefined'
    );
    expect(erroPeticao(erro({ error: 'DRIVE_OFF' }), t)).toBe(
      'RAMON.PETICOES.DRIVE_OFF|undefined'
    );
    expect(erroPeticao(erro({ errors: ['Informe o comprovante'] }), t)).toBe(
      'Informe o comprovante'
    );
    expect(erroPeticao({}, t, 'RAMON.PETICOES.DRIVE_ERRO')).toBe(
      'RAMON.PETICOES.DRIVE_ERRO|undefined'
    );
  });
});
