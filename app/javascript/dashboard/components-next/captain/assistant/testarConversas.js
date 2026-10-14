// Conversas do Testar (I-PG3): ficam guardadas enquanto a página do hub estiver aberta — trocar de tela
// ou de assistente não apaga. ponytail: memória da página (F5 ou fechar a aba limpa); nada do caso fica
// gravado no navegador. Upgrade, se pedirem sobreviver ao F5: sessionStorage por assistente.
import { reactive } from 'vue';

const conversas = reactive({});
// Roteiro em teste (F2/F5): a seleção ('' = sem roteiro · SEM_TESE = lead sem tese · id da tese), o modo simulado e
// o que o servidor devolve a cada resposta (nada é gravado). thesisId muda quando o "assunto" escolhe a tese.
const roteiros = reactive({});
export const SEM_TESE = 'sem_tese';
const teseDa = selecao =>
  selecao && selecao !== SEM_TESE ? Number(selecao) : null;

export const garantirConversa = id => {
  if (!conversas[id]) conversas[id] = [];
  if (!roteiros[id])
    roteiros[id] = {
      selecao: '',
      modo: 'rascunho',
      thesisId: null,
      estado: null,
      painel: null,
    };
};

export const conversaDe = id => conversas[id] || [];

export const roteiroDe = id => roteiros[id];

// Trocar a seleção recomeça o roteiro do teste (a conversa fica — limpe-a para começar do zero).
export const escolherRoteiro = (id, selecao) => {
  Object.assign(roteiros[id], {
    selecao,
    thesisId: teseDa(selecao),
    estado: null,
    painel: null,
  });
};

// O que vai no corpo do playground; null = Testar sem roteiro.
export const pedidoDoRoteiro = roteiro =>
  roteiro?.selecao
    ? {
        thesis_id: roteiro.thesisId,
        estado: roteiro.estado,
        modo: roteiro.modo,
      }
    : null;

export const limparConversa = id => {
  conversas[id] = [];
  // a seleção e o modo ficam; o roteiro recomeça junto com a conversa (inclusive a tese que o "assunto" escolheu)
  const roteiro = roteiros[id];
  if (roteiro)
    Object.assign(roteiro, {
      thesisId: teseDa(roteiro.selecao),
      estado: null,
      painel: null,
    });
};
