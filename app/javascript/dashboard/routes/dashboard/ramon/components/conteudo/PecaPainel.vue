<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';

const props = defineProps({ pecaId: { type: Number, required: true } });
const emit = defineEmits(['changed', 'close']);

const { t } = useI18n();
const peca = ref(null);
const nota = ref('');
const ocupado = ref(false);

const campos = computed(() =>
  Object.entries(peca.value?.conteudo?.fields || {}).filter(
    ([, valor]) => typeof valor === 'string' && valor.trim()
  )
);

const carregar = async () => {
  const { data } = await RamonConteudoAPI.show(props.pecaId);
  peca.value = data;
};

const agir = async acao => {
  ocupado.value = true;
  try {
    const { data } = await acao();
    peca.value = data;
    emit('changed');
  } catch (e) {
    useAlert(e?.response?.data?.error || t('RAMON.CONTEUDO.ACAO_ERRO'));
    await carregar();
    emit('changed');
  } finally {
    ocupado.value = false;
  }
};

watch(() => props.pecaId, carregar, { immediate: true });
</script>

<template>
  <aside
    v-if="peca"
    class="fixed inset-y-0 right-0 z-50 flex w-full max-w-xl flex-col gap-4 overflow-y-auto bg-n-solid-1 p-6 shadow-xl"
  >
    <header class="flex items-start justify-between gap-2">
      <h2 class="text-lg font-medium text-n-slate-12">{{ peca.gancho }}</h2>
      <Button ghost slate sm icon="i-lucide-x" @click="emit('close')" />
    </header>
    <p v-if="peca.erro" class="rounded bg-n-ruby-3 p-2 text-sm text-n-ruby-11">
      {{ peca.erro }}
    </p>

    <template v-if="peca.status === 'rascunho'">
      <dl class="flex flex-col gap-2 text-sm">
        <div v-for="[chave, valor] in campos" :key="chave">
          <dt class="text-xs text-n-slate-10">{{ chave }}</dt>
          <dd class="whitespace-pre-line text-n-slate-12">{{ valor }}</dd>
        </div>
      </dl>
      <p class="whitespace-pre-line rounded bg-n-alpha-1 p-3 text-sm">
        {{ peca.legenda }}
      </p>
      <textarea
        v-model="nota"
        class="rounded border border-n-weak p-2 text-sm"
        :placeholder="t('RAMON.CONTEUDO.NOTA_PLACEHOLDER')"
      />
      <div class="flex gap-2">
        <Button
          :label="t('RAMON.CONTEUDO.APROVAR')"
          :is-loading="ocupado"
          data-testid="peca-aprovar"
          @click="agir(() => RamonConteudoAPI.aprovar(peca.id))"
        />
        <Button
          ruby
          outline
          :label="t('RAMON.CONTEUDO.REPROVAR')"
          :is-loading="ocupado"
          @click="agir(() => RamonConteudoAPI.reprovar(peca.id, nota))"
        />
      </div>
    </template>

    <p
      v-else-if="['aprovado', 'montando'].includes(peca.status)"
      class="text-sm text-n-slate-11"
    >
      {{ t('RAMON.CONTEUDO.MONTANDO_INFO') }}
    </p>
  </aside>
</template>
