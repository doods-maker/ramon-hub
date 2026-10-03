import { ref } from 'vue';

// Seções recolhíveis abertas do painel do lead (redesign v2: as abas viraram
// linhas recolhíveis) — compartilhadas entre o painel da conversa e a gaveta
// do Kanban (mesma chave de localStorage).
const KEY = 'ramon_lead_panel_abertas';
// Atalho do Ctrl K (useRamonLeadHotKeys) ainda grava a aba antiga: abre a
// seção equivalente uma vez e apaga o pedido.
const TAB_KEY = 'ramon_lead_panel_tab';
const TAB_PARA_SECAO = {
  simulador: 'calculos',
  documentos: 'documentos',
  contrato: 'contrato',
  historico: 'historico',
  playbook: 'playbook',
};

const salvar = abertas => {
  try {
    localStorage.setItem(KEY, JSON.stringify(abertas));
  } catch (e) {
    // localStorage indisponível: seguimos sem persistir
  }
};

const ler = () => {
  try {
    const salvas = JSON.parse(localStorage.getItem(KEY) || '[]');
    const abertas = Array.isArray(salvas) ? salvas : [];
    const daAba = TAB_PARA_SECAO[localStorage.getItem(TAB_KEY)];
    localStorage.removeItem(TAB_KEY);
    if (!daAba || abertas.includes(daAba)) return abertas;
    salvar([...abertas, daAba]);
    return [...abertas, daAba];
  } catch (e) {
    return [];
  }
};

export function useLeadPanelSecoes() {
  const abertas = ref(ler());
  const alternar = id => {
    abertas.value = abertas.value.includes(id)
      ? abertas.value.filter(aberta => aberta !== id)
      : [...abertas.value, id];
    salvar(abertas.value);
  };
  const abrir = id => {
    if (!abertas.value.includes(id)) alternar(id);
  };
  return { abertas, alternar, abrir };
}
