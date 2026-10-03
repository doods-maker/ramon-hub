import { defineStore } from 'pinia';
import ChegadasAPI from 'dashboard/api/ramonChegadas';

export const useChegadasStore = defineStore('chegadas', {
  state: () => ({ itens: [], podeAvisar: false, vistos: [] }),

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
    marcarVisto(id) {
      this.vistos.push(id);
    },
  },
});
