import {
  formatarValor,
  fraseDoRegistro,
  linhaCsv,
  mudancasDoRegistro,
  paraCsv,
  quandoSp,
  quemFez,
  rotaDoAlvo,
} from '../registroAcoes';

// t de teste: devolve a chave com os parâmetros em ordem (sem i18n real).
const t = (key, params) =>
  params && Object.keys(params).length
    ? `${key} ${Object.values(params).join(' | ')}`
    : key;
const F = 'RAMON.REGISTRO.FRASE';

const lead = (mudancas, extra = {}) => ({
  modelo: 'Lead',
  tipo: 'lead',
  acao: 'update',
  mudancas,
  alvo: { lead_id: 7, contato_id: 3, nome: 'Maria' },
  ...extra,
});

describe('fraseDoRegistro', () => {
  it.each([
    [
      lead({ lead_stage_id: ['Qualificação', 'Negociação'] }),
      `${F}.LEAD_ETAPA Qualificação | Negociação`,
    ],
    [lead({ sdr_id: [null, 'Bruno'] }), `${F}.LEAD_SDR — | Bruno`],
    [lead({ value: ['1500.0', '2500.0'] }), `${F}.LEAD_VALOR`],
    [
      lead({ won_at: ['2026-10-01T12:00:00Z', null] }),
      `${F}.LEAD_DESFEZ_GANHO`,
    ],
    [lead({}, { acao: 'destroy' }), `${F}.LEAD_EXCLUIU`],
  ])('lead: %#', (registro, esperado) => {
    expect(fraseDoRegistro(registro, t)).toContain(esperado);
  });

  it('etapa ganha a frase mesmo quando o won_at muda junto', () => {
    const r = lead({
      lead_stage_id: ['Proposta', 'Fechado'],
      won_at: [null, '2026-10-06T12:00:00Z'],
    });
    expect(fraseDoRegistro(r, t)).toBe(`${F}.LEAD_ETAPA Proposta | Fechado`);
  });

  it('contato: anonimização, em massa, mesclagem e edição', () => {
    const contato = (extra, mudancas = {}) => ({
      modelo: 'Contact',
      acao: 'update',
      mudancas,
      ...extra,
    });
    expect(fraseDoRegistro(contato({ comentario: 'anonimizado' }), t)).toBe(
      `${F}.CONTATO_ANONIMIZOU`
    );
    expect(
      fraseDoRegistro(contato({ comentario: 'anonimizado_em_massa' }), t)
    ).toBe(`${F}.CONTATO_ANONIMIZOU_MASSA`);
    expect(
      fraseDoRegistro(contato({ comentario: 'mesclado:9', acao: 'destroy' }), t)
    ).toBe(`${F}.CONTATO_MESCLOU`);
    expect(fraseDoRegistro(contato({}, { blocked: [false, true] }), t)).toBe(
      `${F}.CONTATO_BLOQUEOU`
    );
    expect(
      fraseDoRegistro(
        contato({}, { phone_number: ['1', '2'], email: ['a', 'b'] }),
        t
      )
    ).toBe(
      `${F}.CONTATO_EDITOU RAMON.REGISTRO.CAMPO.PHONE_NUMBER, RAMON.REGISTRO.CAMPO.EMAIL`
    );
  });

  it('conversa: atribuiu, transferiu e tirou', () => {
    const conversa = assignee => ({
      modelo: 'Conversation',
      acao: 'update',
      mudancas: { assignee_id: assignee },
      alvo: { conversa: 42 },
    });
    expect(fraseDoRegistro(conversa([null, 'Ana']), t)).toBe(
      `${F}.CONVERSA_ATRIBUIU 42 | — | Ana`
    );
    expect(fraseDoRegistro(conversa(['Ana', 'Bruno']), t)).toBe(
      `${F}.CONVERSA_TRANSFERIU 42 | Ana | Bruno`
    );
    expect(fraseDoRegistro(conversa(['Ana', null]), t)).toBe(
      `${F}.CONVERSA_DESATRIBUIU 42 | Ana | —`
    );
  });

  it('dinheiro e acesso falam da pessoa do registro', () => {
    const alvo = { nome: 'Bruno' };
    expect(
      fraseDoRegistro(
        {
          modelo: 'ExtratoFechado',
          acao: 'create',
          alvo,
          mudancas: {
            papel: [null, 'sdr'],
            competencia: [null, '2026-09-01'],
          },
        },
        t
      )
    ).toBe(`${F}.EXTRATO_FECHOU Bruno | RAMON.EXTRATO.PAPEL.sdr | 09/2026`);
    expect(
      fraseDoRegistro(
        {
          modelo: 'MetaComercial',
          acao: 'update',
          alvo,
          mudancas: { meta: [20, 25] },
        },
        t
      )
    ).toBe(`${F}.META_MUDOU Bruno | 20 | 25`);
    expect(
      fraseDoRegistro(
        {
          modelo: 'AccountUser',
          acao: 'update',
          alvo,
          mudancas: { role: [0, 1] },
        },
        t
      )
    ).toBe(
      `${F}.ACESSO_PAPEL Bruno | RAMON.REGISTRO.PAPEL_CONTA.AGENTE | RAMON.REGISTRO.PAPEL_CONTA.ADMIN`
    );
  });

  it('modelo desconhecido cai na frase genérica', () => {
    expect(fraseDoRegistro({ modelo: 'Inbox', acao: 'update' }, t)).toBe(
      `${F}.EDITOU`
    );
  });
});

describe('formatação', () => {
  it('formata dinheiro, mês, nulo e valor anonimizado', () => {
    expect(formatarValor('value', '1500.0', t)).toMatch(/R\$\s1\.500,00/);
    expect(formatarValor('competencia', '2026-09-01', t)).toBe('09/2026');
    expect(formatarValor('data_nascimento', '1980-02-03', t)).toBe(
      '03/02/1980'
    );
    expect(formatarValor('name', null, t)).toBe('—');
    expect(formatarValor('cpf', '[anonimizado]', t)).toBe(
      'RAMON.REGISTRO.ANONIMIZADO'
    );
  });

  it('quando sai no horário de Brasília', () => {
    expect(quandoSp('2026-10-06T17:32:00Z')).toBe('06/10/2026 14:32');
  });

  it('antes → depois só na edição, com número em mono', () => {
    const r = lead({
      value: ['1500.0', '2500.0'],
      lost_reason: [null, 'Sem qualidade'],
    });
    const [valor, motivo] = mudancasDoRegistro(r, t);
    expect(valor).toMatchObject({ campo: 'value', mono: true });
    expect(motivo).toMatchObject({
      antes: '—',
      depois: 'Sem qualidade',
      mono: false,
    });
    expect(mudancasDoRegistro({ ...r, acao: 'destroy' }, t)).toEqual([]);
  });

  it('sem autor = automação', () => {
    expect(quemFez({ quem: null }, t)).toBe('RAMON.REGISTRO.AUTOMACAO');
    expect(quemFez({ quem: { nome: 'Ana' } }, t)).toBe('Ana');
  });
});

describe('rotaDoAlvo', () => {
  it('lead vai pro dossiê, contato pra Linha da Vida, sem alvo = nada', () => {
    expect(rotaDoAlvo({ lead_id: 7, contato_id: 3 })).toEqual({
      name: 'ramon_lead_dossie',
      params: { leadId: 7 },
    });
    expect(rotaDoAlvo({ contato_id: 3 })).toEqual({
      name: 'ramon_linha_da_vida',
      params: { contactId: 3 },
    });
    expect(rotaDoAlvo(null)).toBeNull();
  });
});

describe('CSV', () => {
  it('linha com frase e antes → depois; aspas escapadas e BOM', () => {
    const r = lead(
      { lead_stage_id: ['A', 'B'] },
      { quando: '2026-10-06T17:32:00Z', quem: { nome: 'Ana "Gestora"' } }
    );
    const linha = linhaCsv(r, t);
    expect(linha[0]).toBe('06/10/2026 14:32');
    expect(linha[5]).toBe('RAMON.REGISTRO.CAMPO.LEAD_STAGE_ID: A → B');
    const csv = paraCsv([linha]);
    expect(csv.charCodeAt(0)).toBe(0xfeff);
    expect(csv).toContain('"Ana ""Gestora"""');
  });
});
