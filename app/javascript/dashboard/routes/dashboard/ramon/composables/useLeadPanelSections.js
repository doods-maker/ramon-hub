import { ref } from 'vue';

// Aba ativa do painel do lead — compartilhada entre o painel da conversa e a
// gaveta do Kanban (mesma chave de localStorage). Substitui o antigo estado de
// acordeões (ramon_lead_panel_sections) do redesign 1f.
const TAB_KEY = 'ramon_lead_panel_tab';
export const LEAD_PANEL_TABS = [
  'resumo',
  'playbook',
  'ia',
  'simulador',
  'contrato',
  'historico',
];

const readStored = () => {
  try {
    const stored = localStorage.getItem(TAB_KEY);
    return LEAD_PANEL_TABS.includes(stored) ? stored : 'resumo';
  } catch (e) {
    return 'resumo';
  }
};

export function useLeadPanelTabs() {
  const activeTab = ref(readStored());
  const setTab = id => {
    if (!LEAD_PANEL_TABS.includes(id)) return;
    activeTab.value = id;
    try {
      localStorage.setItem(TAB_KEY, id);
    } catch (e) {
      // localStorage indisponível: seguimos sem persistir
    }
  };
  return { activeTab, setTab };
}
