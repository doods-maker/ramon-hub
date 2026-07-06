// Export do funil (item 14 do 4b). Separador ';' + BOM = abre certo no
// Excel pt-BR sem assistente de importacao.
const buildColumns = channelLabels => [
  ['nome', l => l.name],
  ['telefone', l => l.contact_phone],
  ['etapa', l => l.stage_name],
  ['tese', l => l.thesis_name],
  ['beneficio', l => l.benefit_type_name],
  ['prioridade', l => l.lead_priority_name],
  ['valor', l => l.value],
  ['origem', l => l.source],
  ['canal', l => channelLabels[l.channel] || l.channel || ''],
  ['sdr', l => l.sdr_name],
  ['closer', l => l.closer_name],
  ['motivo_perda', l => l.lost_reason],
];

const cell = value => {
  const s = value == null ? '' : String(value);
  return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

// channels = cat\u00E1logo do leadConfig store ([{ key, label }]) para traduzir a
// chave crua do lead na coluna leg\u00EDvel.
export const leadsToCsv = (leads, channels = []) => {
  const channelLabels = Object.fromEntries(
    channels.map(c => [c.key, c.label])
  );
  const columns = buildColumns(channelLabels);
  const header = columns.map(([label]) => label).join(';');
  const rows = leads.map(lead =>
    columns.map(([, pick]) => cell(pick(lead))).join(';')
  );
  return `\uFEFF${[header, ...rows].join('\n')}`;
};
