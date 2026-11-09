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

  it('chip confirmar acende por prefixo de caminho, sem falso positivo', () => {
    const doencas = { saude: { doencas: [{ cid: 'M54' }] } };
    expect(
      colheitaCampos(doencas, ['saude.doencas[0].cid'])[0].confirmar
    ).toBe(true);
    const outro = { acidente: { data_x: '2025-03-14' } };
    expect(colheitaCampos(outro, ['acidente.data'])[0].confirmar).toBe(false);
  });

  it('valor de escolha troca _ por espaço', () => {
    const dados = { incapacidade: { motivo: 'sem_justa_causa' } };
    expect(colheitaCampos(dados, [])[0].valor).toBe('sem justa causa');
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

  it('formata objeto aninhado e lista de objetos sem perder campos', () => {
    const dados = {
      cliente: {
        representante: { nome: 'Ana', parentesco: 'filha', motivo: null },
      },
      saude: {
        doencas: [
          { nome: 'lombalgia', cid: 'M54.5', diagnostico_em: '2023-02-10' },
        ],
      },
      outras_teses_sinal: [{ tese: 'B36', motivo: 'acidente no trajeto' }],
    };
    expect(colheitaCampos(dados, [])).toEqual([
      {
        chave: 'cliente.representante',
        valor: 'nome: Ana · parentesco: filha',
        confirmar: false,
      },
      {
        chave: 'outras_teses_sinal',
        valor: 'tese: B36 · motivo: acidente no trajeto',
        confirmar: false,
      },
      {
        chave: 'saude.doencas',
        valor: 'nome: lombalgia · cid: M54.5 · diagnostico em: 10/02/2023',
        confirmar: false,
      },
    ]);
  });

  it('mantém colheita antiga do B36 com tratamentos em lista de texto', () => {
    expect(
      colheitaCampos(
        { sequela: { tratamentos: ['fisioterapia', 'cirurgia'] } },
        []
      )
    ).toEqual([
      {
        chave: 'sequela.tratamentos',
        valor: 'fisioterapia, cirurgia',
        confirmar: false,
      },
    ]);
  });

  it('benefício mostra a DER e blocos desconhecidos vêm no fim', () => {
    const dados = {
      zzz: { a: 'x' },
      beneficios: [{ especie: 'B31', der: '2025-01-02' }],
    };
    expect(colheitaCampos(dados, []).map(c => c.valor)).toEqual([
      'B31 · DER 02/01/2025',
      'x',
    ]);
  });

  it('sem dados devolve lista vazia', () => {
    expect(colheitaCampos(null, null)).toEqual([]);
  });
});
