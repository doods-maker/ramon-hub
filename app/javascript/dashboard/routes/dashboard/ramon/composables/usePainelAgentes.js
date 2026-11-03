// Onde está o painel dos agentes para esta pessoa (ADR 0013). Menu, abas e tela
// dividem o mesmo pedido; `url` vazio = sem acesso.
import { ref } from 'vue';
import RamonPainelAgentesAPI from 'dashboard/api/ramonPainelAgentes';

const url = ref('');
const carregado = ref(false);
let pedido = null;

export const usePainelAgentes = () => {
  pedido ??= RamonPainelAgentesAPI.get()
    .then(({ data }) => {
      url.value = data.url || '';
    })
    .catch(() => {})
    .finally(() => {
      carregado.value = true;
    });
  return { url, carregado };
};
