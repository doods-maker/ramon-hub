<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';
import { paraInputLocal } from '../../helpers/dataLocal';
import PostPrevia from './PostPrevia.vue';

const props = defineProps({ pecaId: { type: Number, required: true } });
const emit = defineEmits(['changed', 'close']);

const { t } = useI18n();
const peca = ref(null);
const nota = ref('');
const ocupado = ref(false);
const legenda = ref('');
const refazerCards = ref([]);
const quando = ref('');

const campos = computed(() =>
  Object.entries(peca.value?.conteudo?.fields || {}).filter(
    ([, valor]) => typeof valor === 'string' && valor.trim()
  )
);

const carregar = async () => {
  const { data } = await RamonConteudoAPI.show(props.pecaId);
  peca.value = data;
  legenda.value = data.legenda || '';
  quando.value = paraInputLocal(data.sugestao_horario || data.agendado_para);
};

const agir = async acao => {
  ocupado.value = true;
  try {
    const { data } = await acao();
    peca.value = data;
    legenda.value = data.legenda || '';
    quando.value = paraInputLocal(data.sugestao_horario || data.agendado_para);
    refazerCards.value = [];
    emit('changed');
  } catch (e) {
    useAlert(e?.response?.data?.error || t('RAMON.CONTEUDO.ACAO_ERRO'));
    await carregar();
    emit('changed');
  } finally {
    ocupado.value = false;
  }
};

// Legenda editada e não salva iria perdida: salva antes de agendar/publicar.
const comLegenda = acao => () => {
  if (legenda.value === (peca.value.legenda || '')) return acao();
  return RamonConteudoAPI.atualizarLegenda(peca.value.id, legenda.value).then(
    acao
  );
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

    <template
      v-if="
        ['montado', 'agendado', 'falhou', 'publicado'].includes(peca.status)
      "
    >
      <PostPrevia :imagens="peca.imagens || []" :legenda="legenda" />
      <template v-if="['montado', 'agendado'].includes(peca.status)">
        <textarea
          v-model="legenda"
          rows="8"
          class="rounded border border-n-weak p-2 text-sm"
        />
        <Button
          sm
          outline
          :label="t('RAMON.CONTEUDO.SALVAR_LEGENDA')"
          :disabled="legenda === peca.legenda"
          @click="
            agir(() => RamonConteudoAPI.atualizarLegenda(peca.id, legenda))
          "
        />
      </template>
      <div
        v-if="peca.status === 'montado'"
        class="flex flex-wrap items-center gap-2 text-sm"
      >
        <span>{{ t('RAMON.CONTEUDO.REFAZER') }}</span>
        <label
          v-for="n in (peca.imagens || []).length"
          :key="n"
          class="flex items-center gap-1"
        >
          <input v-model="refazerCards" type="checkbox" :value="n" />
          {{ n }}
        </label>
        <Button
          sm
          slate
          :label="t('RAMON.CONTEUDO.REFAZER_BOTAO')"
          :disabled="!refazerCards.length"
          @click="agir(() => RamonConteudoAPI.refazer(peca.id, refazerCards))"
        />
      </div>
      <div v-if="peca.status === 'montado'" class="flex flex-col gap-2">
        <input
          v-model="quando"
          data-testid="agendar-quando"
          type="datetime-local"
          class="rounded border border-n-weak p-2 text-sm"
        />
        <div class="flex gap-2">
          <Button
            data-testid="agendar"
            :label="t('RAMON.CONTEUDO.AGENDAR')"
            :disabled="!quando || ocupado"
            :is-loading="ocupado"
            @click="
              agir(
                comLegenda(() =>
                  RamonConteudoAPI.agendar(
                    peca.id,
                    new Date(quando).toISOString()
                  )
                )
              )
            "
          />
          <Button
            outline
            :label="t('RAMON.CONTEUDO.PUBLICAR_AGORA')"
            :disabled="ocupado"
            @click="
              agir(comLegenda(() => RamonConteudoAPI.publicarAgora(peca.id)))
            "
          />
        </div>
      </div>
      <div
        v-if="peca.status === 'agendado'"
        class="flex flex-col gap-2 text-sm"
      >
        <span>
          {{
            t('RAMON.CONTEUDO.AGENDADA_PARA', {
              quando: new Date(peca.agendado_para).toLocaleString('pt-BR', {
                dateStyle: 'short',
                timeStyle: 'short',
              }),
            })
          }}
        </span>
        <div class="flex gap-2">
          <Button
            outline
            :label="t('RAMON.CONTEUDO.PUBLICAR_AGORA')"
            :disabled="ocupado"
            @click="
              agir(comLegenda(() => RamonConteudoAPI.publicarAgora(peca.id)))
            "
          />
          <Button
            ruby
            outline
            :label="t('RAMON.CONTEUDO.CANCELAR')"
            :disabled="ocupado"
            @click="agir(() => RamonConteudoAPI.cancelarAgendamento(peca.id))"
          />
        </div>
      </div>
      <Button
        v-if="peca.status === 'falhou'"
        :label="t('RAMON.CONTEUDO.TENTAR_DE_NOVO')"
        :disabled="ocupado"
        @click="agir(() => RamonConteudoAPI.tentarDeNovo(peca.id))"
      />
      <a
        v-if="peca.permalink"
        :href="peca.permalink"
        target="_blank"
        rel="noopener noreferrer"
        class="text-sm text-n-blue-11 underline"
      >
        {{ t('RAMON.CONTEUDO.VER_NO_INSTAGRAM') }}
      </a>
    </template>
  </aside>
</template>
