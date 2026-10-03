// Quadros salvos do Funil (ui_settings.ramon_lead_boards).
export const BOARD_PALETTE = [
  '#2563eb',
  '#0ea5e9',
  '#8b5cf6',
  '#db2777',
  '#16a34a',
  '#64748b',
];

// Conversão do legado ramon_lead_views [{name, filters}] → quadros completos.
// Roda uma única vez na leitura (SavedViews) e persiste no formato novo.
export const legacyToBoards = views =>
  (views || []).map((view, index) => ({
    id: Date.now() + index,
    name: view.name,
    color: BOARD_PALETTE[index % BOARD_PALETTE.length],
    filters: { ...(view.filters || {}) },
    collapsed: [],
    view: 'columns',
    groupBy: 'thesis',
  }));
