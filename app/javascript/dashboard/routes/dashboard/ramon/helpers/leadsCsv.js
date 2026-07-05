// Export do funil (item 14 do 4b). Separador ';' + BOM = abre certo no
// Excel pt-BR sem assistente de importacao.
const COLUMNS = [
  ['nome', l => l.name],
  ['telefone', l => l.contact_phone],
  ['etapa', l => l.stage_name],
  ['tese', l => l.thesis_name],
  ['beneficio', l => l.benefit_type_name],
  ['prioridade', l => l.lead_priority_name],
  ['valor', l => l.value],
  ['origem', l => l.source],
  ['sdr', l => l.sdr_name],
  ['closer', l => l.closer_name],
  ['motivo_perda', l => l.lost_reason],
];

const cell = value => {
  const s = value == null ? '' : String(value);
  return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

export const leadsToCsv = leads => {
  const header = COLUMNS.map(([label]) => label).join(';');
  const rows = leads.map(lead =>
    COLUMNS.map(([, pick]) => cell(pick(lead))).join(';')
  );
  return `\uFEFF${[header, ...rows].join('\n')}`;
};
