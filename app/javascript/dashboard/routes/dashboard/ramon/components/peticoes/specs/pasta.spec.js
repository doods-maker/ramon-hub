import {
  erroPeticao,
  mensagemAlerta,
  mensagemAviso,
  mensagemRecusa,
  podeConfirmar,
} from '../helpers';

const t = (k, p) => `${k}|${p?.detalhe ?? ''}`;

describe('peticoes/helpers · pela pasta', () => {
  it('mensagemRecusa traduz código com e sem detalhe', () => {
    expect(mensagemRecusa('marcador:[CONFERIR]', t)).toBe(
      'RAMON.PETICOES.PASTA.RECUSA.marcador|[CONFERIR]'
    );
    expect(mensagemRecusa('sem_pdf', t)).toBe(
      'RAMON.PETICOES.PASTA.RECUSA.sem_pdf|'
    );
  });

  it('mensagemRecusa mantém os dois-pontos do nome do arquivo', () => {
    expect(mensagemRecusa('formato:a:b.docx', t)).toBe(
      'RAMON.PETICOES.PASTA.RECUSA.formato|a:b.docx'
    );
  });

  it('mensagemAviso e mensagemAlerta usam o próprio grupo', () => {
    expect(mensagemAviso('subpastas:Antigos', t)).toBe(
      'RAMON.PETICOES.PASTA.AVISO.subpastas|Antigos'
    );
    expect(mensagemAviso('espelho_vazio', t)).toBe(
      'RAMON.PETICOES.PASTA.AVISO.espelho_vazio|'
    );
    expect(mensagemAlerta('cpf_diferente', t)).toBe(
      'RAMON.PETICOES.PASTA.ALERTA.cpf_diferente|'
    );
  });

  it('erroPeticao traduz os erros da pasta', () => {
    const erro = error => ({ response: { data: { error } } });
    expect(erroPeticao(erro('pasta_invalida'), t)).toContain('PASTA_INVALIDA');
    expect(erroPeticao(erro('em_leitura'), t)).toContain('EM_LEITURA');
    expect(erroPeticao(erro('pacote_da_pasta'), t)).toContain(
      'PACOTE_DA_PASTA'
    );
  });

  describe('podeConfirmar', () => {
    const boa = {
      leitura: { estado: 'lida', recusas: [] },
      alertas: ['cpf_diferente'],
      problemas: [],
    };
    it('libera com leitura lida, sem recusa, alerta conferido e sem problema', () =>
      expect(podeConfirmar(boa, ['cpf_diferente'])).toBe(true));
    it('trava com alerta sem marcar', () =>
      expect(podeConfirmar(boa, [])).toBe(false));
    it('trava com recusa', () =>
      expect(
        podeConfirmar(
          { ...boa, leitura: { estado: 'lida', recusas: ['sem_pdf'] } },
          ['cpf_diferente']
        )
      ).toBe(false));
    it('trava enquanto lê e no erro', () => {
      ['lendo', 'erro'].forEach(estado =>
        expect(
          podeConfirmar({ ...boa, leitura: { estado, recusas: [] } }, [
            'cpf_diferente',
          ])
        ).toBe(false)
      );
    });
    it('trava com problema do pacote', () =>
      expect(
        podeConfirmar({ ...boa, problemas: ['sem_principal'] }, [
          'cpf_diferente',
        ])
      ).toBe(false));
  });
});
