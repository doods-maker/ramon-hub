<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';
import { paraInputLocal } from '../../helpers/dataLocal';
import {
  LIMITE_CARACTERES,
  LIMITE_HASHTAGS,
  contarLegenda,
  tomDoLimite,
} from '../../helpers/legendaIg';
import PostPrevia from './PostPrevia.vue';
import ConfirmModal from '../ConfirmModal.vue';
import { AVISO, CAMPO, SECAO, TEXTAREA, TITULO, TOM } from '../../helpers/ui';

const props = defineProps({
  pecaId: { type: Number, required: true },
  // Sem token do IG não dá pra agendar nem publicar (index devolve token_ig).
  tokenIg: { type: Boolean, default: true },
  // Status da peça na lista do quadro (que recarrega sozinho): mudou, recarrega.
  status: { type: String, default: '' },
});
const emit = defineEmits(['changed', 'close']);

const { t } = useI18n();
const peca = ref(null);
const nota = ref('');
const ocupado = ref(false);
const legenda = ref('');
const refazerCards = ref([]);
const quando = ref('');
// Publicar/tentar de novo vai ao ar de verdade: passa por confirmação.
const confirmacao = ref(null);
// Falha ambígua (pode ter ido ao ar): só libera depois do "conferi".
const conferido = ref(false);

const TOM_TEXTO = {
  slate: 'text-n-slate-10',
  amber: 'text-n-amber-11',
  ruby: 'text-n-ruby-11',
};
const contagem = computed(() => contarLegenda(legenda.value));
const contadores = computed(() => [
  {
    chave: 'caracteres',
    texto: t('RAMON.CONTEUDO.CONTADOR_CARACTERES', {
      n: contagem.value.caracteres.toLocaleString('pt-BR'),
      limite: LIMITE_CARACTERES.toLocaleString('pt-BR'),
    }),
    tom: TOM_TEXTO[tomDoLimite(contagem.value.caracteres, LIMITE_CARACTERES)],
  },
  {
    chave: 'hashtags',
    texto: t('RAMON.CONTEUDO.CONTADOR_HASHTAGS', {
      n: contagem.value.hashtags,
      limite: LIMITE_HASHTAGS,
    }),
    tom: TOM_TEXTO[tomDoLimite(contagem.value.hashtags, LIMITE_HASHTAGS)],
  },
]);

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
    conferido.value = false;
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

const pedirConfirmacao = (textos, acao) => {
  confirmacao.value = { ...textos, acao };
};
const confirmar = () => {
  const { acao } = confirmacao.value;
  confirmacao.value = null;
  agir(acao);
};
const publicarAgora = () =>
  pedirConfirmacao(
    {
      titulo: t('RAMON.CONTEUDO.CONFIRMAR_PUBLICAR'),
      mensagem: t('RAMON.CONTEUDO.CONFIRMAR_PUBLICAR_MSG'),
      rotulo: t('RAMON.CONTEUDO.PUBLICAR_AGORA'),
    },
    comLegenda(() => RamonConteudoAPI.publicarAgora(peca.value.id))
  );
const tentarDeNovo = () =>
  pedirConfirmacao(
    {
      titulo: t('RAMON.CONTEUDO.CONFIRMAR_TENTAR'),
      mensagem: t('RAMON.CONTEUDO.CONFIRMAR_TENTAR_MSG'),
      rotulo: t('RAMON.CONTEUDO.TENTAR_DE_NOVO'),
    },
    () => RamonConteudoAPI.tentarDeNovo(peca.value.id, conferido.value)
  );

// Faixa de andamento: publicando agora, ou agendada com horário vencido (o
// cron de 1 min ainda vai pegar).
const andamento = computed(() => {
  if (peca.value?.status === 'publicando') return 'PUBLICANDO';
  const vencida =
    peca.value?.status === 'agendado' &&
    new Date(peca.value.agendado_para) <= new Date();
  return vencida ? 'NA_FILA' : null;
});

watch(() => props.pecaId, carregar, { immediate: true });
watch(
  () => props.status,
  novo => {
    if (peca.value && novo && novo !== peca.value.status) carregar();
  }
);
</script>

<template>
  <aside
    v-if="peca"
    class="fixed inset-y-0 right-0 z-50 flex w-full max-w-xl flex-col gap-4 overflow-y-auto border-l border-n-weak bg-n-solid-2 p-6 shadow-xl"
  >
    <header class="flex items-start justify-between gap-2">
      <h2 class="text-lg font-semibold leading-snug text-n-slate-12">
        {{ peca.gancho }}
      </h2>
      <Button ghost slate sm icon="i-lucide-x" @click="emit('close')" />
    </header>
    <p
      v-if="andamento"
      data-testid="peca-andamento"
      :class="[AVISO, TOM.blue]"
      class="flex items-center gap-2"
    >
      <span class="i-lucide-loader-circle size-3.5 animate-spin" />
      {{
        andamento === 'PUBLICANDO'
          ? t('RAMON.CONTEUDO.PUBLICANDO')
          : t('RAMON.CONTEUDO.NA_FILA')
      }}
    </p>
    <p v-if="peca.erro" :class="[AVISO, TOM.ruby]">
      {{ peca.erro }}
    </p>
    <p
      v-if="!tokenIg && ['montado', 'agendado', 'falhou'].includes(peca.status)"
      :class="[AVISO, TOM.amber]"
    >
      {{ t('RAMON.CONTEUDO.SEM_TOKEN') }}
    </p>

    <template v-if="peca.status === 'rascunho'">
      <dl class="flex flex-col gap-3 text-sm">
        <div v-for="[chave, valor] in campos" :key="chave">
          <dt :class="TITULO">{{ chave }}</dt>
          <dd class="mt-0.5 whitespace-pre-line text-n-slate-12">
            {{ valor }}
          </dd>
        </div>
      </dl>
      <p
        class="whitespace-pre-line rounded-lg bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12"
      >
        {{ peca.legenda }}
      </p>
      <textarea
        v-model="nota"
        :class="TEXTAREA"
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
          faded
          :label="t('RAMON.CONTEUDO.REPROVAR')"
          :is-loading="ocupado"
          @click="agir(() => RamonConteudoAPI.reprovar(peca.id, nota))"
        />
      </div>
    </template>

    <p
      v-else-if="['aprovado', 'montando'].includes(peca.status)"
      :class="[AVISO, TOM.slate]"
    >
      {{ t('RAMON.CONTEUDO.MONTANDO_INFO') }}
    </p>

    <template
      v-if="
        ['montado', 'agendado', 'publicando', 'falhou', 'publicado'].includes(
          peca.status
        )
      "
    >
      <PostPrevia
        :imagens="peca.imagens || []"
        :legenda="legenda"
        :colaboradores="peca.colaboradores || []"
      />
      <template v-if="['montado', 'agendado'].includes(peca.status)">
        <div class="flex flex-col gap-1">
          <textarea v-model="legenda" rows="8" :class="TEXTAREA" />
          <p
            data-testid="legenda-contador"
            class="flex justify-end gap-3 font-mono text-[11px] tabular-nums"
          >
            <span v-for="c in contadores" :key="c.chave" :class="c.tom">
              {{ c.texto }}
            </span>
          </p>
        </div>
        <Button
          sm
          slate
          faded
          class="self-start"
          :label="t('RAMON.CONTEUDO.SALVAR_LEGENDA')"
          :disabled="legenda === peca.legenda"
          @click="
            agir(() => RamonConteudoAPI.atualizarLegenda(peca.id, legenda))
          "
        />
      </template>
      <div
        v-if="peca.status === 'montado'"
        :class="SECAO"
        class="flex flex-wrap items-center gap-3 text-sm text-n-slate-12"
      >
        <span>{{ t('RAMON.CONTEUDO.REFAZER') }}</span>
        <label
          v-for="n in (peca.imagens || []).length"
          :key="n"
          class="flex items-center gap-1 font-mono tabular-nums"
        >
          <input v-model="refazerCards" type="checkbox" :value="n" />
          {{ n }}
        </label>
        <Button
          sm
          slate
          faded
          :label="t('RAMON.CONTEUDO.REFAZER_BOTAO')"
          :disabled="!refazerCards.length"
          @click="agir(() => RamonConteudoAPI.refazer(peca.id, refazerCards))"
        />
      </div>
      <div
        v-if="peca.status === 'montado'"
        :class="SECAO"
        class="flex flex-col gap-2"
      >
        <input
          v-model="quando"
          data-testid="agendar-quando"
          type="datetime-local"
          :class="CAMPO"
          class="font-mono"
        />
        <div class="flex gap-2">
          <Button
            data-testid="agendar"
            :label="t('RAMON.CONTEUDO.AGENDAR')"
            :disabled="!quando || ocupado || !tokenIg"
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
            slate
            faded
            :label="t('RAMON.CONTEUDO.PUBLICAR_AGORA')"
            data-testid="publicar-agora"
            :disabled="ocupado || !tokenIg"
            @click="publicarAgora"
          />
        </div>
      </div>
      <div
        v-if="peca.status === 'agendado'"
        :class="SECAO"
        class="flex flex-col gap-2 text-sm text-n-slate-12"
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
            slate
            faded
            :label="t('RAMON.CONTEUDO.PUBLICAR_AGORA')"
            data-testid="publicar-agora"
            :disabled="ocupado || !tokenIg"
            @click="publicarAgora"
          />
          <Button
            ruby
            faded
            :label="t('RAMON.CONTEUDO.CANCELAR')"
            :disabled="ocupado"
            @click="agir(() => RamonConteudoAPI.cancelarAgendamento(peca.id))"
          />
        </div>
      </div>
      <div
        v-if="peca.status === 'falhou'"
        class="flex flex-col items-start gap-2"
      >
        <label
          v-if="peca.ambigua"
          class="flex items-center gap-2 text-sm text-n-slate-12"
        >
          <input
            v-model="conferido"
            data-testid="conferi-instagram"
            type="checkbox"
          />
          {{ t('RAMON.CONTEUDO.CONFERI') }}
        </label>
        <div class="flex gap-2">
          <Button
            data-testid="tentar-de-novo"
            :label="t('RAMON.CONTEUDO.TENTAR_DE_NOVO')"
            :disabled="ocupado || !tokenIg || (peca.ambigua && !conferido)"
            @click="tentarDeNovo"
          />
          <Button
            data-testid="voltar-prontas"
            slate
            faded
            :label="t('RAMON.CONTEUDO.VOLTAR_PRONTAS')"
            :disabled="ocupado || (peca.ambigua && !conferido)"
            @click="
              agir(() => RamonConteudoAPI.voltarProntas(peca.id, conferido))
            "
          />
        </div>
      </div>
      <a
        v-if="peca.permalink"
        :href="peca.permalink"
        target="_blank"
        rel="noopener noreferrer"
        class="self-start text-sm text-n-blue-11 hover:underline"
      >
        {{ t('RAMON.CONTEUDO.VER_NO_INSTAGRAM') }}
      </a>
    </template>
    <ConfirmModal
      v-if="confirmacao"
      :title="confirmacao.titulo"
      :message="confirmacao.mensagem"
      :confirm-label="confirmacao.rotulo"
      confirm-color="blue"
      @confirm="confirmar"
      @cancel="confirmacao = null"
    />
  </aside>
</template>
