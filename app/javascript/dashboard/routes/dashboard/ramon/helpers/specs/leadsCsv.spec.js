import { leadsToCsv } from '../leadsCsv';

describe('leadsToCsv', () => {
  it('gera cabecalho + linhas com ; e BOM', () => {
    const csv = leadsToCsv([
      {
        name: 'Joao',
        contact_phone: '+554899999',
        stage_name: 'Novo',
        thesis_name: null,
        benefit_type_name: 'Auxilio-acidente',
        lead_priority_name: null,
        value: 9800.5,
        source: 'lp-meta',
        sdr_name: null,
        closer_name: null,
        lost_reason: null,
      },
    ]);
    // BOM sempre via escape \uFEFF, nunca o caractere literal
    expect(csv.startsWith('\uFEFF')).toBe(true);
    const [header, row] = csv.slice(1).split('\n');
    expect(header).toBe(
      'nome;telefone;etapa;tese;beneficio;prioridade;valor;origem;sdr;closer;motivo_perda'
    );
    expect(row).toBe(
      'Joao;+554899999;Novo;;Auxilio-acidente;;9800.5;lp-meta;;;'
    );
  });

  it('escapa ; aspas e quebra de linha', () => {
    const csv = leadsToCsv([
      { name: 'A;B', source: 'diz "oi"', stage_name: 'X\nY' },
    ]);
    const row = csv.slice(1).split('\n').slice(1).join('\n');
    expect(row).toContain('"A;B"');
    expect(row).toContain('"diz ""oi"""');
    expect(row).toContain('"X\nY"');
  });
});
