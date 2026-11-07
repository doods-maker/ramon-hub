import { colheitaCampos } from '../colheitaCampos';

describe('colheitaCampos', () => {
  it('lista só o que a IA preencheu, por seção, na ordem do schema', () => {
    const dados = {
      acidente: { data: '2025-03-14', tipo: 'trabalho', cat_emitida: 'sim' },
      cliente: { nome_completo: null, profissao: 'pedreiro', estado_civil: '' },
      sequela: { descricao: 'perda de força no punho', tratamentos: [] },
    };
    expect(colheitaCampos(dados, [])).toEqual([
      { chave: 'cliente.profissao', valor: 'pedreiro', confirmar: false },
      { chave: 'acidente.data', valor: '14/03/2025', confirmar: false },
      { chave: 'acidente.tipo', valor: 'trabalho', confirmar: false },
      { chave: 'acidente.cat_emitida', valor: 'sim', confirmar: false },
      {
        chave: 'sequela.descricao',
        valor: 'perda de força no punho',
        confirmar: false,
      },
    ]);
  });

  it('marca o que a IA ouviu de forma incerta', () => {
    const dados = { acidente: { data: '2025-03-14' } };
    expect(colheitaCampos(dados, ['acidente.data'])[0].confirmar).toBe(true);
  });

  it('benefício vira uma linha só com espécie, datas e situação', () => {
    const dados = {
      beneficios: [
        {
          nb: null,
          especie: 'B91',
          dib: '2025-03-15',
          dcb: '2025-07-20',
          situacao: 'cessado',
        },
        { especie: null, dib: null, dcb: null, situacao: null },
      ],
    };
    expect(colheitaCampos(dados, [])).toEqual([
      {
        chave: 'beneficios',
        valor: 'B91 · DIB 15/03/2025 · DCB 20/07/2025 · cessado',
        confirmar: false,
      },
    ]);
  });

  it('lista vira texto e sim/não lógico vira sim/não', () => {
    const dados = {
      sequela: { tratamentos: ['cirurgia', 'fisioterapia'] },
      qualificacao: { aposentado: false },
    };
    expect(colheitaCampos(dados, []).map(c => c.valor)).toEqual([
      'não',
      'cirurgia, fisioterapia',
    ]);
  });

  it('sem dados devolve lista vazia', () => {
    expect(colheitaCampos(null, null)).toEqual([]);
  });
});
