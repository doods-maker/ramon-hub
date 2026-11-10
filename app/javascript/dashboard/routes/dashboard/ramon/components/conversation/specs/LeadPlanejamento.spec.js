import { mount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import LeadPlanejamento from '../LeadPlanejamento.vue';

const tWithParams = (k, params) =>
  params ? `${k}:${Object.values(params).join(',')}` : k;
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: tWithParams }) }));
vi.mock('dashboard/api/leads', () => ({
  default: {
    planejamento: vi.fn(),
    planejamentoGerar: vi.fn(),
    planejamentoGeracao: vi.fn(),
    planejamentoArquivo: vi.fn(),
  },
}));

const lead = { id: 13 };

const montar = (props = {}) =>
  mount(LeadPlanejamento, {
    props: { lead, ...props },
    global: { mocks: { $t: tWithParams } },
  });

// Caso fictício, no formato do `dados` do motor.
const dadosMotor = (extra = {}) => ({
  nome: 'Segurada Ficticia',
  formato_textos: 'aprovado',
  calculo_data: '09/11/2026',
  aposentadoria: { data: '10/01/2032', regra: 'regra dos pontos' },
  cenarios: [
    { nome: 'Mínimo', v: 1518, rmi: 1518, custo: 166.98, lead: 'texto L' },
    { nome: 'Teto', v: 8157.41, rmi: 4200.5, custo: 897.31, sugestao: true },
  ],
  sugestao: { curta: 'Seguir pelo teto', titulo: 'Sugestão' },
  parar: { data: '10/01/2036', rmi: 1518 },
  pode: [{ t: 'Pode', p: 'texto pode' }],
  ...extra,
});

const resposta = (dados = dadosMotor()) => ({
  data: {
    dados,
    forma_sugerida: {
      forma: 'carne_20',
      salario_atual: 3000,
      motivo: 'recolhimento próprio',
    },
    avisos: ['aviso do motor'],
  },
});

const clicar = async (w, id) => {
  await w.find(`[data-testid="${id}"]`).trigger('click');
  await flushPromises();
};

const calculado = async () => {
  LeadsAPI.planejamento.mockResolvedValue(resposta());
  const w = montar();
  await clicar(w, 'planejamento-comecar');
  await clicar(w, 'planejamento-calcular');
  return w;
};

describe('LeadPlanejamento', () => {
  afterEach(() => vi.useRealTimers());

  it('não chama o motor ao montar', () => {
    montar();
    expect(LeadsAPI.planejamento).not.toHaveBeenCalled();
  });

  it('começar: 1ª chamada sem perfil e formulário com a forma sugerida', async () => {
    LeadsAPI.planejamento.mockResolvedValue(resposta());
    const w = montar();
    await clicar(w, 'planejamento-comecar');

    expect(LeadsAPI.planejamento).toHaveBeenCalledWith(13, {
      segurado_nome: undefined,
    });
    expect(w.find('[data-testid="planejamento-forma"]').element.value).toBe(
      'carne_20'
    );
    expect(
      w.find('[data-testid="planejamento-salario-atual"]').element.value
    ).toBe('3000');
    expect(w.text()).toContain('recolhimento próprio');
    expect(w.find('[data-testid="planejamento-resultado"]').exists()).toBe(
      false
    );
  });

  it('calcular manda o perfil confirmado', async () => {
    LeadsAPI.planejamento.mockResolvedValue(resposta());
    const w = montar({ seguradoNome: 'Segurada Ficticia' });
    await clicar(w, 'planejamento-comecar');
    await w
      .find('[data-testid="planejamento-empresa"]')
      .setValue('Empresa Ficticia');
    await clicar(w, 'planejamento-calcular');

    expect(LeadsAPI.planejamento).toHaveBeenLastCalledWith(13, {
      segurado_nome: 'Segurada Ficticia',
      perfil: expect.objectContaining({
        forma: 'carne_20',
        empresa: 'Empresa Ficticia',
        salario_atual: '3000',
        descarte_pontos: 'nao',
      }),
    });
    const resumo = w.find('[data-testid="planejamento-resultado"]').text();
    expect(resumo).toContain('10/01/2032');
    expect(resumo).toContain('Seguir pelo teto');
    expect(resumo).toContain('aviso do motor');
    expect(w.find('[data-testid="planejamento-cenario-1"]').text()).toContain(
      'Teto'
    );
  });

  it('salário do emprego e facultativo só aparecem na forma que usa', async () => {
    LeadsAPI.planejamento.mockResolvedValue(resposta());
    const w = montar();
    await clicar(w, 'planejamento-comecar');
    const existe = id => w.find(`[data-testid="${id}"]`).exists();
    expect(existe('planejamento-salario-emprego')).toBe(false);
    expect(existe('planejamento-facultativo')).toBe(false);

    await w
      .find('[data-testid="planejamento-forma"]')
      .setValue('pro_labore_mais_salario');
    expect(existe('planejamento-salario-emprego')).toBe(true);
    expect(existe('planejamento-facultativo')).toBe(true);
  });

  it('rascunho de textos mostra "aguardando aprovação dos textos"', async () => {
    LeadsAPI.planejamento.mockResolvedValue(
      resposta(dadosMotor({ formato_textos: 'rascunho', versao: 'curta' }))
    );
    const w = montar();
    await clicar(w, 'planejamento-comecar');
    await clicar(w, 'planejamento-calcular');

    expect(w.text()).toContain('PLANEJAMENTO_AGUARDANDO_TEXTOS');
    expect(w.text()).toContain('PLANEJAMENTO_VERSAO_CURTA');
  });

  it('motor desatualizado aparece como mensagem, sem quebrar', async () => {
    LeadsAPI.planejamento.mockRejectedValue({
      response: {
        status: 503,
        data: {
          error:
            'motor de cálculos desatualizado: /planejamento/previdenciario não existe',
        },
      },
    });
    const w = montar();
    await clicar(w, 'planejamento-comecar');

    expect(w.find('[data-testid="planejamento-error"]').text()).toContain(
      'motor de cálculos desatualizado'
    );
    expect(w.find('[data-testid="planejamento-comecar"]').exists()).toBe(true);
  });

  it('gerar manda o dados editado e consulta até ficar pronto', async () => {
    vi.useFakeTimers();
    const w = await calculado();
    await w
      .find('[data-testid="planejamento-texto-pode.0.p"]')
      .setValue('texto editado');
    LeadsAPI.planejamentoGerar.mockResolvedValue({ data: { calculo_id: 77 } });
    LeadsAPI.planejamentoGeracao
      .mockResolvedValueOnce({ data: { estado: 'gerando' } })
      .mockResolvedValueOnce({
        data: {
          estado: 'pronto',
          drive: { pasta_url: 'https://drive.google.com/drive/folders/x' },
        },
      });
    await clicar(w, 'planejamento-gerar');

    const [id, corpo] = LeadsAPI.planejamentoGerar.mock.calls[0];
    expect(id).toBe(13);
    expect(corpo.dados.pode[0].p).toBe('texto editado');
    expect(corpo.perfil.forma).toBe('carne_20');

    await vi.advanceTimersByTimeAsync(2000);
    expect(LeadsAPI.planejamentoGeracao).toHaveBeenCalledWith(13, 77);
    expect(w.find('[data-testid="planejamento-baixar-pdf"]').exists()).toBe(
      false
    );
    await vi.advanceTimersByTimeAsync(2000);

    expect(
      w.find('[data-testid="planejamento-drive"] a').attributes('href')
    ).toBe('https://drive.google.com/drive/folders/x');
    expect(w.find('[data-testid="planejamento-baixar-pdf"]').exists()).toBe(
      true
    );
    expect(w.find('[data-testid="planejamento-baixar-memoria"]').exists()).toBe(
      true
    );
  });

  it('Drive falhou: download continua e mostra o erro do Drive', async () => {
    vi.useFakeTimers();
    const w = await calculado();
    LeadsAPI.planejamentoGerar.mockResolvedValue({ data: { calculo_id: 77 } });
    LeadsAPI.planejamentoGeracao.mockResolvedValue({
      data: {
        estado: 'pronto',
        drive: null,
        drive_erro: 'não salvou no Drive: timeout',
      },
    });
    await clicar(w, 'planejamento-gerar');
    await vi.advanceTimersByTimeAsync(2000);

    expect(w.find('[data-testid="planejamento-drive"]').text()).toContain(
      'não salvou no Drive: timeout'
    );
    expect(w.find('[data-testid="planejamento-baixar-pdf"]').exists()).toBe(
      true
    );
  });

  it('baixar usa o arquivo do cálculo gerado', async () => {
    vi.useFakeTimers();
    const { createObjectURL, revokeObjectURL } = global.URL;
    global.URL.createObjectURL = vi.fn(() => 'blob:mock');
    global.URL.revokeObjectURL = vi.fn();
    const clique = vi
      .spyOn(HTMLAnchorElement.prototype, 'click')
      .mockImplementation(function guardaNome() {
        clique.nome = this.download;
      });
    const w = await calculado();
    LeadsAPI.planejamentoGerar.mockResolvedValue({ data: { calculo_id: 77 } });
    LeadsAPI.planejamentoGeracao.mockResolvedValue({
      data: { estado: 'pronto', drive: null, drive_motivo: 'sem_cliente' },
    });
    const blob = new Blob(['%PDF'], { type: 'application/pdf' });
    LeadsAPI.planejamentoArquivo.mockResolvedValue({
      data: blob,
      headers: {
        'content-disposition':
          'attachment; filename="x.xlsx"; filename*=UTF-8\'\'Mem%C3%B3ria%20de%20c%C3%A1lculo%20-%20Fulana.xlsx',
      },
    });
    await clicar(w, 'planejamento-gerar');
    await vi.advanceTimersByTimeAsync(2000);

    expect(w.text()).toContain('PLANEJAMENTO_DRIVE_SO_DOWNLOAD');
    await clicar(w, 'planejamento-baixar-memoria');
    expect(LeadsAPI.planejamentoArquivo).toHaveBeenCalledWith(
      13,
      77,
      'memoria'
    );
    expect(global.URL.createObjectURL).toHaveBeenCalledWith(blob);
    expect(clique.nome).toBe('Memória de cálculo - Fulana.xlsx');
    expect(global.URL.revokeObjectURL).toHaveBeenCalledWith('blob:mock');

    clique.mockRestore();
    Object.assign(global.URL, { createObjectURL, revokeObjectURL });
  });

  it('para de consultar depois de 60 tentativas', async () => {
    vi.useFakeTimers();
    const w = await calculado();
    LeadsAPI.planejamentoGerar.mockResolvedValue({ data: { calculo_id: 77 } });
    LeadsAPI.planejamentoGeracao.mockResolvedValue({
      data: { estado: 'gerando' },
    });
    await clicar(w, 'planejamento-gerar');
    await vi.advanceTimersByTimeAsync(2000 * 61);

    expect(LeadsAPI.planejamentoGeracao).toHaveBeenCalledTimes(60);
    expect(w.find('[data-testid="planejamento-error"]').text()).toContain(
      'PLANEJAMENTO_DEMOROU'
    );
    // tentar de novo gera outra vez
    await clicar(w, 'planejamento-retry');
    expect(LeadsAPI.planejamentoGerar).toHaveBeenCalledTimes(2);
  });

  it('estado vazio (linha sem geração) para de consultar sem quebrar', async () => {
    vi.useFakeTimers();
    const w = await calculado();
    LeadsAPI.planejamentoGerar.mockResolvedValue({ data: { calculo_id: 77 } });
    LeadsAPI.planejamentoGeracao.mockResolvedValue({ data: null });
    await clicar(w, 'planejamento-gerar');
    await vi.advanceTimersByTimeAsync(2000 * 3);

    expect(LeadsAPI.planejamentoGeracao).toHaveBeenCalledTimes(1);
    expect(w.find('[data-testid="planejamento-gerar"]').exists()).toBe(true);
  });

  it('erro na geração mostra a mensagem e mantém as edições', async () => {
    vi.useFakeTimers();
    const w = await calculado();
    const campo = '[data-testid="planejamento-texto-pode.0.p"]';
    await w.find(campo).setValue('texto editado');
    LeadsAPI.planejamentoGerar.mockResolvedValue({ data: { calculo_id: 77 } });
    LeadsAPI.planejamentoGeracao.mockResolvedValue({
      data: { estado: 'erro', erro: 'o PDF não pôde ser gerado: marcador' },
    });
    await clicar(w, 'planejamento-gerar');
    await vi.advanceTimersByTimeAsync(2000);

    expect(w.find('[data-testid="planejamento-error"]').text()).toContain(
      'o PDF não pôde ser gerado: marcador'
    );
    expect(w.find(campo).element.value).toBe('texto editado');
  });

  it('422 ao calcular aparece em português e mantém o resultado editado', async () => {
    const w = await calculado();
    const campo = '[data-testid="planejamento-texto-pode.0.p"]';
    await w.find(campo).setValue('texto editado');
    LeadsAPI.planejamento.mockRejectedValueOnce({
      response: { status: 422, data: { error: 'salário atual inválido' } },
    });
    await clicar(w, 'planejamento-calcular');

    expect(w.find('[data-testid="planejamento-error"]').text()).toContain(
      'salário atual inválido'
    );
    expect(w.find(campo).element.value).toBe('texto editado');
  });

  it('erro do download vindo como blob vira mensagem', async () => {
    vi.useFakeTimers();
    const w = await calculado();
    LeadsAPI.planejamentoGerar.mockResolvedValue({ data: { calculo_id: 77 } });
    LeadsAPI.planejamentoGeracao.mockResolvedValue({
      data: { estado: 'pronto', drive: null, drive_motivo: 'drive_desligado' },
    });
    LeadsAPI.planejamentoArquivo.mockRejectedValue({
      response: {
        status: 404,
        data: new Blob([
          JSON.stringify({ error: 'arquivo expirou — gere de novo' }),
        ]),
      },
    });
    await clicar(w, 'planejamento-gerar');
    await vi.advanceTimersByTimeAsync(2000);
    await clicar(w, 'planejamento-baixar-pdf');
    // FileReader do jsdom agenda a leitura num timer (falso aqui)
    await vi.advanceTimersByTimeAsync(10);
    await flushPromises();

    expect(w.find('[data-testid="planejamento-error"]').text()).toContain(
      'arquivo expirou'
    );
    expect(w.find('[data-testid="planejamento-drive"]').text()).toContain(
      'PLANEJAMENTO_DRIVE_SO_DOWNLOAD'
    );
    // arquivo expirou: tentar de novo gera de novo, não baixa o 404 outra vez
    await clicar(w, 'planejamento-retry');
    expect(LeadsAPI.planejamentoGerar).toHaveBeenCalledTimes(2);
    expect(LeadsAPI.planejamentoArquivo).toHaveBeenCalledTimes(1);
  });

  it('reabrir do histórico restaura perfil e dados sem chamar o motor', async () => {
    const w = montar({
      inicial: { perfil: { forma: 'pro_labore' }, dados: dadosMotor() },
    });
    await flushPromises();

    expect(LeadsAPI.planejamento).not.toHaveBeenCalled();
    expect(w.find('[data-testid="planejamento-forma"]').element.value).toBe(
      'pro_labore'
    );
    expect(w.find('[data-testid="planejamento-resultado"]').text()).toContain(
      '10/01/2032'
    );
    expect(w.find('[data-testid="planejamento-gerar"]').exists()).toBe(true);
  });

  it('linha antiga do histórico (sem dados) abre no começo', () => {
    const w = montar({ inicial: { cenarios: [{ nome: 'conservador' }] } });
    expect(w.find('[data-testid="planejamento-comecar"]').exists()).toBe(true);
    expect(w.find('[data-testid="planejamento-resultado"]').exists()).toBe(
      false
    );
  });

  it('para o polling ao desmontar', async () => {
    vi.useFakeTimers();
    const w = await calculado();
    LeadsAPI.planejamentoGerar.mockResolvedValue({ data: { calculo_id: 77 } });
    LeadsAPI.planejamentoGeracao.mockResolvedValue({
      data: { estado: 'gerando' },
    });
    await clicar(w, 'planejamento-gerar');
    await vi.advanceTimersByTimeAsync(2000);
    const chamadas = LeadsAPI.planejamentoGeracao.mock.calls.length;
    w.unmount();
    await vi.advanceTimersByTimeAsync(2000 * 5);

    expect(LeadsAPI.planejamentoGeracao).toHaveBeenCalledTimes(chamadas);
  });

  it('consulta em andamento ao desmontar não agenda outra', async () => {
    vi.useFakeTimers();
    const w = await calculado();
    LeadsAPI.planejamentoGerar.mockResolvedValue({ data: { calculo_id: 77 } });
    let responder;
    LeadsAPI.planejamentoGeracao.mockReturnValueOnce(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    LeadsAPI.planejamentoGeracao.mockResolvedValue({
      data: { estado: 'gerando' },
    });
    await clicar(w, 'planejamento-gerar');
    await vi.advanceTimersByTimeAsync(2000);
    expect(LeadsAPI.planejamentoGeracao).toHaveBeenCalledTimes(1);

    w.unmount();
    responder({ data: { estado: 'gerando' } });
    await vi.advanceTimersByTimeAsync(10000);

    expect(LeadsAPI.planejamentoGeracao).toHaveBeenCalledTimes(1);
  });

  it('gerar em andamento ao desmontar não começa a consultar', async () => {
    vi.useFakeTimers();
    const w = await calculado();
    let responder;
    LeadsAPI.planejamentoGerar.mockReturnValueOnce(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    await clicar(w, 'planejamento-gerar');
    w.unmount();
    responder({ data: { calculo_id: 77 } });
    await vi.advanceTimersByTimeAsync(10000);

    expect(LeadsAPI.planejamentoGeracao).not.toHaveBeenCalled();
  });
});
