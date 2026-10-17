// Conversas do Testar (I-PG3): ficam guardadas enquanto a página do hub estiver aberta — trocar de tela
// ou de assistente não apaga. ponytail: memória da página (F5 ou fechar a aba limpa); nada do caso fica
// gravado no navegador. Upgrade, se pedirem sobreviver ao F5: sessionStorage por assistente.
import { reactive } from 'vue';

const conversas = reactive({});
// Roteiro em teste (F2/F5): a seleção ('' = sem roteiro · SEM_TESE = lead sem tese · id da tese) e
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
      thesisId: null,
      estado: null,
      painel: null,
      perfil: null,
    };
};

export const conversaDe = id => conversas[id] || [];

export const roteiroDe = id => roteiros[id];

// Trocar a seleção recomeça o roteiro do teste (a conversa fica — limpe-a para começar do zero).
// "Sem roteiro" também para o teste do perfil da tela (ele só vai junto do roteiro).
export const escolherRoteiro = (id, selecao) => {
  Object.assign(roteiros[id], {
    selecao,
    thesisId: teseDa(selecao),
    estado: null,
    painel: null,
    perfil: selecao ? roteiros[id].perfil : null,
  });
};

// "Testar este perfil" (Como a IA atende): o cfg da tela, mesmo não salvo, vai em cada pedido, com a tese do alvo
// (sem tese = lead sem tese). A conversa recomeça.
export const testarPerfil = (id, perfil, thesisId) => {
  garantirConversa(id);
  conversas[id] = [];
  Object.assign(roteiros[id], {
    selecao: thesisId ? String(thesisId) : SEM_TESE,
    thesisId: thesisId || null,
    estado: null,
    painel: null,
    perfil,
  });
};

export const pararTesteDoPerfil = id => {
  roteiros[id].perfil = null;
};

// O que vai no corpo do playground; null = Testar sem roteiro.
export const pedidoDoRoteiro = roteiro =>
  roteiro?.selecao
    ? {
        thesis_id: roteiro.thesisId,
        estado: roteiro.estado,
        ...(roteiro.perfil ? { perfil: roteiro.perfil } : {}),
      }
    : null;

export const limparConversa = id => {
  conversas[id] = [];
  // a seleção fica; o roteiro recomeça junto com a conversa (inclusive a tese que o "assunto" escolheu)
  const roteiro = roteiros[id];
  if (roteiro)
    Object.assign(roteiro, {
      thesisId: teseDa(roteiro.selecao),
      estado: null,
      painel: null,
    });
};
