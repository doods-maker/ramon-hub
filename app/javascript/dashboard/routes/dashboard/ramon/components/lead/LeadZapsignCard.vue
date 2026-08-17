<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadsAPI from 'dashboard/api/leads';
import { stripCpf } from '../../helpers/cpf';

const props = defineProps({ lead: { type: Object, required: true } });
const emit = defineEmits(['completeData']);

defineOptions({ name: 'LeadZapsignCard' });
const { t } = useI18n();

// ZapSign (item 21, fluxo A): botão gera contrato+procuração pré-preenchidos
// e devolve o link de assinatura — nada é enviado ao cliente automaticamente.
// Fallback local da resposta: se o websocket estiver caído, o lead da store não
// recebe o zapsign novo e o botão continuaria armado — 2º clique = 2º contrato.
const zapsignLocal = ref(null);
watch(
  () => props.lead?.id,
  () => {
    zapsignLocal.value = null;
  }
);
const zapsign = computed(
  () => props.lead?.custom_attributes?.zapsign || zapsignLocal.value
);
// Modelos da conta ZapSign: o cartão vale pra qualquer tese, o closer escolhe
// o modelo. Pré-seleção só chuta pela tese; ZapSign fora do ar trava o botão.
const templates = ref([]);
const templateId = ref(null);
const templatesError = ref(false);

const semAcento = texto =>
  (texto || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '');

// ponytail: casa qualquer palavra (>3 letras) da tese no nome do modelo — chute
// grosseiro, o closer confirma no select. Sinônimo/apelido de modelo pede mapa.
const guessTemplate = list => {
  const palavras = semAcento(props.lead?.thesis_name)
    .split(/[\s-]+/)
    .filter(w => w.length > 3);
  const match = list.find(tpl =>
    palavras.some(palavra => semAcento(tpl.name).includes(palavra))
  );
  return (match || list[0])?.token || null;
};

onMounted(async () => {
  try {
    const { data } = await LeadsAPI.zapsignTemplates();
    templates.value = data;
    templateId.value = guessTemplate(data);
  } catch (error) {
    templatesError.value = true;
  }
});

// Antes de gerar só dá pra prever o que o painel edita; depois de gerado, o
// backend devolve a lista completa (faltando) com as variáveis do modelo.
// ponytail: pré-geração checa só CPF — espelhar as 12 variáveis do
// ZapsignContractService aqui seria duplicar o serviço no front.
const missing = computed(() => {
  if (zapsign.value)
    return (zapsign.value.faltando || []).map(f => f.replace(/[{}]/g, ''));
  return stripCpf(props.lead?.contact_cpf || '').length === 11
    ? []
    : [t('RAMON.DRAWER.PESSOA.CPF')];
});

const loading = ref(false);
const generate = async () => {
  if (loading.value || missing.value.length) return;
  loading.value = true;
  try {
    const { data } = await LeadsAPI.createZapsign(
      props.lead.id,
      templateId.value
    );
    zapsignLocal.value = data;
    useAlert(
      data.faltando?.length
        ? t('RAMON.ZAPSIGN.MISSING', { count: data.faltando.length })
        : t('RAMON.ZAPSIGN.CREATED')
    );
  } catch (error) {
    useAlert(t('RAMON.ZAPSIGN.ERROR'));
  } finally {
    loading.value = false;
  }
};

const copyLink = async () => {
  try {
    await copyTextToClipboard(zapsign.value.sign_url);
    useAlert(t('RAMON.ZAPSIGN.COPIED'));
  } catch (error) {
    useAlert(t('RAMON.DOCS.COPY_FAILED'));
  }
};
</script>

<template>
  <div
    data-testid="zapsign-card"
    class="rounded-xl p-3 bg-n-solid-1 border border-n-weak"
  >
    <div class="flex items-center gap-2">
      <span class="i-lucide-pen-line size-4 shrink-0 text-n-iris-11" />
      <p class="text-xs font-semibold text-n-iris-11">
        {{ $t('RAMON.ZAPSIGN.CARD_TITLE') }}
      </p>
      <span
        v-if="missing.length"
        data-testid="zapsign-missing"
        class="ml-auto text-[10px] text-n-slate-10"
      >
        {{ $t('RAMON.ZAPSIGN.MISSING_COUNT', { count: missing.length }) }}
      </span>
    </div>

    <p
      v-if="missing.length"
      class="mt-1.5 text-[11.5px] leading-relaxed text-n-slate-11"
    >
      {{ $t('RAMON.ZAPSIGN.MISSING_HINT') }}
      <span class="text-n-amber-11">{{ missing.join(', ') }}</span>
    </p>
    <p v-else class="mt-1.5 text-[11.5px] leading-relaxed text-n-slate-11">
      {{ $t('RAMON.ZAPSIGN.PREPARED') }}
    </p>

    <template v-if="!zapsign?.sign_url">
      <label class="sr-only" for="zapsign-template">
        {{ $t('RAMON.ZAPSIGN.TEMPLATE_LABEL') }}
      </label>
      <select
        id="zapsign-template"
        v-model="templateId"
        data-testid="zapsign-template"
        :disabled="templatesError || !templates.length"
        class="w-full mt-2 text-xs rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1"
      >
        <option v-for="tpl in templates" :key="tpl.token" :value="tpl.token">
          {{ tpl.name }}
        </option>
      </select>
      <p v-if="templatesError" class="mt-1 text-[11px] text-n-amber-11">
        {{ $t('RAMON.ZAPSIGN.TEMPLATES_ERROR') }}
      </p>
    </template>
    <p v-else class="mt-2 text-[11px] text-n-slate-10">
      {{
        $t('RAMON.ZAPSIGN.TEMPLATE_USED', {
          name: zapsign.template_name || '—',
        })
      }}
    </p>

    <div class="flex flex-wrap items-center gap-1.5 mt-2.5">
      <template v-if="zapsign?.sign_url">
        <a
          :href="zapsign.sign_url"
          target="_blank"
          rel="noopener noreferrer"
          data-testid="zapsign-link"
          class="px-3 py-1 text-xs font-semibold rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
        >
          {{ $t('RAMON.ZAPSIGN.OPEN') }}
        </a>
        <button
          type="button"
          data-testid="zapsign-copy"
          class="px-3 py-1 text-xs rounded-lg bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2"
          @click="copyLink"
        >
          {{ $t('RAMON.ZAPSIGN.COPY') }}
        </button>
      </template>
      <button
        v-else
        type="button"
        data-testid="zapsign-generate"
        :disabled="loading || missing.length > 0 || !templateId"
        class="px-3 py-1 text-xs font-semibold rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-50 disabled:cursor-not-allowed"
        @click="generate"
      >
        {{
          loading
            ? $t('RAMON.ZAPSIGN.GENERATING')
            : $t('RAMON.ZAPSIGN.GENERATE_SHORT')
        }}
      </button>
      <button
        v-if="missing.length"
        type="button"
        data-testid="zapsign-complete-data"
        class="px-3 py-1 text-xs rounded-lg bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2"
        @click="emit('completeData')"
      >
        {{ $t('RAMON.ZAPSIGN.COMPLETE_DATA') }}
      </button>
    </div>
  </div>
</template>
