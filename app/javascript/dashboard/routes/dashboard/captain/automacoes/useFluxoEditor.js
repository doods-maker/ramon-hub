// Estado do editor de um fluxo (B2). O quadro (Vue Flow) é dono de nodes/edges;
// o rascunho salva sozinho 1 s depois da última mudança (só se o desenho mudou
// de fato — mexer em seleção/medidas do Vue Flow não salva). Publicar e ensaiar
// sempre salvam antes: o que vale é o que está na tela.
import { computed, ref, watch } from 'vue';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import { deVueFlow, idDoErro, paraVueFlow } from './fluxo';
import { validar } from './validar';

export const useFluxoEditor = () => {
  const fluxo = ref(null);
  const nodes = ref([]);
  const edges = ref([]);
  const salvo = ref('');
  const salvando = ref(false);
  const errosServidor = ref([]);
  const mostrarErros = ref(false);
  let fila = Promise.resolve();
  let timer = null;

  const desenho = computed(() => deVueFlow(nodes.value, edges.value));
  const json = computed(() => JSON.stringify(desenho.value));
  const sujo = computed(
    () => Boolean(fluxo.value) && json.value !== salvo.value
  );
  const errosFront = computed(() => validar(desenho.value));
  const nosComErro = computed(
    () =>
      new Set(
        [
          ...(mostrarErros.value ? errosFront.value.map(e => e.no) : []),
          ...errosServidor.value.map(idDoErro),
        ].filter(Boolean)
      )
  );

  const carregar = async id => {
    const { data } = await RamonFluxosAPI.show(id);
    const vf = paraVueFlow(data.rascunho);
    fluxo.value = data;
    nodes.value = vf.nodes;
    edges.value = vf.edges;
    salvo.value = JSON.stringify(deVueFlow(vf.nodes, vf.edges));
  };

  const recarregarMeta = async () => {
    const { data } = await RamonFluxosAPI.show(fluxo.value.id);
    fluxo.value = data;
  };

  const salvarAgora = async () => {
    if (!sujo.value) return;
    const enviado = json.value;
    salvando.value = true;
    try {
      await RamonFluxosAPI.update(fluxo.value.id, {
        rascunho: JSON.parse(enviado),
      });
      salvo.value = enviado;
    } finally {
      salvando.value = false;
    }
  };
  // Saves em série: um autosave em voo termina antes de publicar/ensaiar
  // salvar de novo (sem corrida nem update fora de ordem).
  const salvar = () => {
    fila = fila.catch(() => {}).then(salvarAgora);
    return fila;
  };
  // ponytail: debounce na mão (o @vueuse/core 12 resolve outra cópia do vue e o watch dele não dispara);
  // falha do autosave fica quieta (sujo continua true) — publicar/ensaiar salvam de novo e mostram o erro
  watch(json, () => {
    errosServidor.value = [];
    clearTimeout(timer);
    timer = setTimeout(() => salvar().catch(() => {}), 1000);
  });

  const atualizar = async attrs => {
    const { data } = await RamonFluxosAPI.update(fluxo.value.id, attrs);
    fluxo.value = { ...fluxo.value, ...data };
  };

  const publicar = async () => {
    mostrarErros.value = true;
    errosServidor.value = [];
    if (errosFront.value.length) return null;
    await salvar();
    try {
      const { data } = await RamonFluxosAPI.publicar(fluxo.value.id);
      await recarregarMeta();
      mostrarErros.value = false;
      return data.versao;
    } catch (e) {
      if (e.response?.status !== 422) throw e;
      errosServidor.value = e.response.data.erros || [];
      return null;
    }
  };

  const ensaiar = async alvo => {
    await salvar();
    const { data } = await RamonFluxosAPI.ensaio(fluxo.value.id, {
      ...alvo,
      usar: 'rascunho',
    });
    return data;
  };

  const rodar = async alvo =>
    (await RamonFluxosAPI.rodar(fluxo.value.id, alvo)).data;

  return {
    fluxo,
    nodes,
    edges,
    desenho,
    sujo,
    salvando,
    errosFront,
    errosServidor,
    mostrarErros,
    nosComErro,
    carregar,
    recarregarMeta,
    salvar,
    atualizar,
    publicar,
    ensaiar,
    rodar,
  };
};
