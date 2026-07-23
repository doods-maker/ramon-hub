// Quadros salvos do Funil (ui_settings.ramon_lead_boards).
export const BOARD_PALETTE = [
  '#c9a97c',
  '#8f9a6b',
  '#6b8f85',
  '#b4785a',
  '#a06e8c',
  '#8d867d',
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
