import {
  SECOES_EDITAVEIS,
  camposEditaveis,
  definirTexto,
} from '../planejamentoTextos';

const dados = () => ({
  nome: 'Ana',
  formato_textos: 'aprovado',
  cenarios: [
    {
      nome: 'Mínimo',
      v: 1518,
      rmi: 2234.62,
      titulo: 'Cenário 1',
      lead: 'L',
      bom: ['a', 'b'],
    },
  ],
  pode: [{ t: 'T', p: 'P' }],
  sugestao: { curta: 'c', titulo: 't', itens: ['i'] },
  documentos: { separar: ['s'], guardar: ['g'] },
  aposentadoria: { data: '16/03/2040', regra: 'regra dos pontos' },
});

describe('planejamentoTextos', () => {
  it('expõe as seções editáveis', () => {
    expect(SECOES_EDITAVEIS).toContain('observacoes_internas');
    expect(SECOES_EDITAVEIS).toContain('melhorias');
  });

  it('lista só as folhas de texto das seções editáveis, na ordem', () => {
    expect(camposEditaveis(dados()).map(c => c.caminho.join('.'))).toEqual([
      'pode.0.t',
      'pode.0.p',
      'sugestao.curta',
      'sugestao.titulo',
      'sugestao.itens.0',
      'cenarios.0.lead',
      'cenarios.0.bom.0',
      'cenarios.0.bom.1',
      'documentos.separar.0',
      'documentos.guardar.0',
    ]);
  });

  it('informa seção e valor de cada campo', () => {
    expect(camposEditaveis(dados())[0]).toEqual({
      secao: 'pode',
      caminho: ['pode', 0, 't'],
      valor: 'T',
    });
  });

  it('versão curta sem cenários: lista melhorias e ignora números', () => {
    const d = {
      versao: 'curta',
      melhorias: [{ t: '+12 meses', p: 'x', rmi: 3000, ok: true, n: null }],
    };
    expect(camposEditaveis(d).map(c => c.caminho.join('.'))).toEqual([
      'melhorias.0.t',
      'melhorias.0.p',
    ]);
  });

  it('melhorias: só t e p; data e regra vêm do motor', () => {
    const d = {
      melhorias: [
        { t: 'Agora', p: 'x', data: '10/11/2026', regra: 'regra da idade' },
      ],
    };
    expect(camposEditaveis(d).map(c => c.caminho.join('.'))).toEqual([
      'melhorias.0.t',
      'melhorias.0.p',
    ]);
    expect(() =>
      definirTexto(d, ['melhorias', 0, 'data'], '01/01/2027')
    ).toThrow();
  });

  it('pendências e observações: só título e texto; o impacto é rótulo do motor', () => {
    const d = {
      pendencias: [{ t: 'Vínculo aberto', imp: 'pode tirar tempo', p: 'x' }],
      observacoes_internas: [{ t: 'Mês baixo', imp: 'conferir', p: 'y' }],
    };
    expect(camposEditaveis(d).map(c => c.caminho.join('.'))).toEqual([
      'pendencias.0.t',
      'pendencias.0.p',
      'observacoes_internas.0.t',
      'observacoes_internas.0.p',
    ]);
  });

  it('versão curta: cenários, sugestão e conferir não vão no PDF, não editam', () => {
    const d = {
      ...dados(),
      versao: 'curta',
      conferir: ['c'],
      melhorias: [{ t: 'Agora', p: 'x' }],
    };
    expect(camposEditaveis(d).map(c => c.secao)).toEqual([
      'pode',
      'pode',
      'melhorias',
      'melhorias',
      'documentos',
      'documentos',
    ]);
  });

  it('seção que é texto solto também é editável', () => {
    const d = { observacoes_internas: 'só advogado' };
    expect(camposEditaveis(d)).toEqual([
      {
        secao: 'observacoes_internas',
        caminho: ['observacoes_internas'],
        valor: 'só advogado',
      },
    ]);
  });

  it('definirTexto troca o texto no lugar', () => {
    const d = dados();
    definirTexto(d, ['cenarios', 0, 'bom', 1], 'novo');
    expect(d.cenarios[0].bom[1]).toBe('novo');
  });

  it('definirTexto recusa número', () => {
    expect(() => definirTexto(dados(), ['cenarios', 0, 'rmi'], '1')).toThrow();
  });

  it('definirTexto recusa texto fora das seções editáveis', () => {
    const d = { ...dados(), calculo_data: '01/01/2026' };
    [
      ['calculo_data'],
      ['aposentadoria', 'data'],
      ['cenarios', 0, 'nome'],
      ['cenarios', 0, 'titulo'],
      ['nome'],
    ].forEach(c => expect(() => definirTexto(d, c, 'x')).toThrow());
    expect(d.aposentadoria.data).toBe('16/03/2040');
  });

  it('definirTexto recusa caminho inexistente e alvo objeto/array', () => {
    const d = dados();
    expect(() => definirTexto(d, ['pode', 9, 't'], 'x')).toThrow();
    expect(() => definirTexto(d, ['nada', 'x'], 'x')).toThrow();
    expect(() => definirTexto(d, ['pode', 0], 'x')).toThrow();
    expect(() => definirTexto(d, ['cenarios', 0, 'bom'], 'x')).toThrow();
    expect(() => definirTexto(d, ['sugestao'], 'x')).toThrow();
  });

  it('definirTexto aceita marcador como texto', () => {
    const d = dados();
    definirTexto(d, ['pode', 0, 'p'], 'em {data_ap} aposenta');
    expect(d.pode[0].p).toBe('em {data_ap} aposenta');
  });
});
