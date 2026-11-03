// Conferência de fases: grupos, tons e as datas da tela (horário de Brasília).
export const GRUPOS = ['atrasada', 'baixa', 'diferente', 'igual'];
export const TOM_DO_GRUPO = {
  atrasada: 'amber',
  baixa: 'slate',
  diferente: 'ruby',
  igual: 'teal',
};

// "2026-10-06" (ou "2026-10-06 14:00:00") → "06/10/2026".
export const dataBr = data =>
  String(data).slice(0, 10).split('-').reverse().join('/');

// Carimbo ISO → { data: "06/10", hora: "14:32" } no fuso de SP.
export const diaMesHora = iso => {
  const fmt = opcoes =>
    new Intl.DateTimeFormat('pt-BR', {
      timeZone: 'America/Sao_Paulo',
      ...opcoes,
    }).format(new Date(iso));
  return {
    data: fmt({ day: '2-digit', month: '2-digit' }),
    hora: fmt({ hour: '2-digit', minute: '2-digit' }),
  };
};

// Quanto a linha soma em cada contador do resumo — para ajustar o resumo
// depois de uma marcação sem pedir a lista de novo.
export const contaNoResumo = l => ({
  conferidos: l.painel_marca ? 1 : 0,
  errados: l.painel_marca === 'errado' ? 1 : 0,
  para_aplicar: l.etapa_id && !l.aplicado_em ? 1 : 0,
});

// { "JUDICIAL": [etapas] } na ordem do ADVBOX, sem a etapa sugerida (ela já
// aparece no topo do seletor).
export const etapasPorGrupo = (etapas, sugeridaId) =>
  etapas.reduce((grupos, e) => {
    if (e.etapa_id !== sugeridaId) (grupos[e.step] ||= []).push(e);
    return grupos;
  }, {});
