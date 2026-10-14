// Conversas do Testar (I-PG3): ficam guardadas enquanto a página do hub estiver aberta — trocar de tela
// ou de assistente não apaga. ponytail: memória da página (F5 ou fechar a aba limpa); nada do caso fica
// gravado no navegador. Upgrade, se pedirem sobreviver ao F5: sessionStorage por assistente.
import { reactive } from 'vue';

const conversas = reactive({});
// Roteiro da tese em teste (F2): a tese escolhida e o estado que o servidor devolve a cada resposta (nada é gravado).
const roteiros = reactive({});

export const garantirConversa = id => {
  if (!conversas[id]) conversas[id] = [];
  if (!roteiros[id])
    roteiros[id] = { thesisId: null, estado: null, painel: null };
};

export const conversaDe = id => conversas[id] || [];

export const roteiroDe = id => roteiros[id];

export const limparConversa = id => {
  conversas[id] = [];
  // a tese escolhida fica; o roteiro recomeça junto com a conversa
  if (roteiros[id]) Object.assign(roteiros[id], { estado: null, painel: null });
};
