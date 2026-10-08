// Conversas do Testar (I-PG3): ficam guardadas enquanto a página do hub estiver aberta — trocar de tela
// ou de assistente não apaga. ponytail: memória da página (F5 ou fechar a aba limpa); nada do caso fica
// gravado no navegador. Upgrade, se pedirem sobreviver ao F5: sessionStorage por assistente.
import { reactive } from 'vue';

const conversas = reactive({});

export const garantirConversa = id => {
  if (!conversas[id]) conversas[id] = [];
};

export const conversaDe = id => conversas[id] || [];

export const limparConversa = id => {
  conversas[id] = [];
};
