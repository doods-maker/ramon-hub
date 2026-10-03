import { defineStore } from 'pinia';
import ChegadasAPI from 'dashboard/api/ramonChegadas';
import { LocalStorage } from 'shared/helpers/localStorage';

// "Entendi" numa escalada sobrevive a recarregar a página.
// ponytail: lista só cresce (ids, bytes por dia); podar se um dia pesar.
const VISTOS_KEY = 'ramon_chegadas_vistos';

export const useChegadasStore = defineStore('chegadas', {
  state: () => ({
    itens: [],
    podeAvisar: false,
    painelPedido: 0,
    vistos: LocalStorage.get(VISTOS_KEY) || [],
  }),

  getters: {
    // O que insiste na tela de quem está logado: chegada pra mim sem resposta,
    // ou chegada que eu avisei e escalou (ninguém respondeu em 3 min).
    alertasPara: state => userId =>
      state.itens.filter(
        c =>
          c.estado !== 'respondido' &&
          (c.destinatario.id === userId ||
            (c.criado_por.id === userId &&
              c.estado === 'escalado' &&
              !state.vistos.includes(c.id)))
      ),
  },

  actions: {
    upsert(chegada) {
      const i = this.itens.findIndex(c => c.id === chegada.id);
      if (i === -1) this.itens.push(chegada);
      else this.itens.splice(i, 1, chegada);
    },
    async carregar() {
      const { data } = await ChegadasAPI.get();
      this.itens = data.payload;
      this.podeAvisar = data.pode_avisar;
    },
    async criar(payload) {
      const { data } = await ChegadasAPI.create(payload);
      this.upsert(data);
      return data;
    },
    async responder(id, resposta) {
      const { data } = await ChegadasAPI.responder(id, resposta);
      this.upsert(data);
    },
    // O botão "Chegou cliente" mora no menu; o painel escuta este contador.
    pedirPainel() {
      this.painelPedido += 1;
    },
    marcarVisto(id) {
      this.vistos.push(id);
      try {
        LocalStorage.set(VISTOS_KEY, this.vistos);
      } catch {
        // storage bloqueado: vale só nesta aba
      }
    },
  },
});
