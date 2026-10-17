<script setup>
// Coluna da esquerda: busca + Escritório / Teses / Caixas sem tese, cada alvo com o estado e a trilha em miniatura.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { CAMPO, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { COR_DO_ESTADO } from 'dashboard/routes/dashboard/ramon/helpers/perfilIa';

const props = defineProps({
  // [{ id, tipo: 'padrao' | 'tese' | 'caixa', nome, estado, personalizado, mini: [estado da Etapa] }]
  alvos: { type: Array, required: true },
});
const selecionado = defineModel({ type: String, required: true });
const { t } = useI18n();
const K = 'RAMON.COMO_IA.LISTA';

const busca = ref('');
const grupos = computed(() => {
  const termo = busca.value.trim().toLowerCase();
  return ['padrao', 'tese', 'caixa']
    .map(tipo => ({
      tipo,
      itens: props.alvos.filter(
        alvo => alvo.tipo === tipo && alvo.nome.toLowerCase().includes(termo)
      ),
    }))
    .filter(grupo => grupo.itens.length);
});
</script>

<template>
  <aside
    class="flex shrink-0 flex-col gap-1 border-b border-n-weak p-3 md:w-72 md:overflow-y-auto md:border-b-0 md:border-r"
  >
    <label class="relative block">
      <span
        class="i-lucide-search absolute left-2.5 top-2 size-4 text-n-slate-10"
        aria-hidden="true"
      />
      <input
        v-model="busca"
        type="search"
        data-testid="busca-alvo"
        :class="CAMPO"
        class="pl-8"
        :placeholder="t(`${K}.BUSCAR`)"
        :aria-label="t(`${K}.BUSCAR`)"
      />
    </label>
    <p v-if="!grupos.length" class="px-2 py-3 text-xs text-n-slate-10">
      {{ t(`${K}.VAZIO`) }}
    </p>
    <section v-for="grupo in grupos" :key="grupo.tipo">
      <h2 class="px-2 pb-1.5 pt-3 text-[11.5px] font-medium text-n-slate-10">
        {{ t(`${K}.GRUPO.${grupo.tipo}`) }}
      </h2>
      <button
        v-for="alvo in grupo.itens"
        :key="alvo.id"
        type="button"
        :data-testid="`alvo-${alvo.id}`"
        :aria-current="alvo.id === selecionado ? 'true' : undefined"
        class="block w-full rounded-lg px-2.5 py-2 text-left"
        :class="alvo.id === selecionado ? TOM.blue : 'hover:bg-n-alpha-2'"
        @click="selecionado = alvo.id"
      >
        <span
          class="block text-[13px] font-medium leading-tight"
          :class="
            alvo.id === selecionado ? 'text-n-blue-11' : 'text-n-slate-12'
          "
        >
          {{ alvo.nome }}
        </span>
        <span class="mt-1.5 flex items-center gap-2">
          <span
            class="whitespace-nowrap text-[11.5px]"
            :class="
              alvo.personalizado
                ? 'font-medium text-n-blue-11'
                : 'text-n-slate-10'
            "
          >
            {{ alvo.estado }}
          </span>
          <span class="ml-auto flex max-w-24 flex-1 gap-0.5" aria-hidden="true">
            <span
              v-for="(estado, i) in alvo.mini"
              :key="i"
              class="h-1 flex-1 rounded-sm"
              :class="COR_DO_ESTADO[estado]"
            />
          </span>
        </span>
      </button>
    </section>
  </aside>
</template>
