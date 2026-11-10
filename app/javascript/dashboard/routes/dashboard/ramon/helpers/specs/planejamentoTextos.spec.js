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
});
