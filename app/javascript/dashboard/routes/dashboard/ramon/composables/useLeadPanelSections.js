import { ref } from 'vue';

// Aberto/recolhido das seções do painel do lead — compartilhado entre o painel
// da conversa e a gaveta do Kanban (mesma chave de localStorage). A gravação é
// read-merge-write por seção: quem toca por último não apaga o que o outro
// componente persistiu.
const SECTIONS_KEY = 'ramon_lead_panel_sections';
const DEFAULTS = {
  resumo: true,
  historico: false,
  playbook: false,
  triagem: false,
  kit: false,
  simulador: false,
};

const readStored = () => {
  try {
    return JSON.parse(localStorage.getItem(SECTIONS_KEY) || '{}');
  } catch (e) {
    return {};
  }
};

export function useLeadPanelSections() {
  const openSections = ref({ ...DEFAULTS, ...readStored() });
  const toggleSection = id => {
    openSections.value[id] = !openSections.value[id];
    try {
      localStorage.setItem(
        SECTIONS_KEY,
        JSON.stringify({ ...readStored(), [id]: openSections.value[id] })
      );
    } catch (e) {
      // localStorage indisponível: seguimos sem persistir
    }
  };
  return { openSections, toggleSection };
}
