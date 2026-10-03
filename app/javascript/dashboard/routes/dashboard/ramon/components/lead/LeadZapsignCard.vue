<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadsAPI from 'dashboard/api/leads';
import { stripCpf } from '../../helpers/cpf';
import Button from 'dashboard/components-next/button/Button.vue';
import { ACAO, CARTAO, TITULO, SELECT } from '../../helpers/ui';

const props = defineProps({ lead: { type: Object, required: true } });
const emit = defineEmits(['completeData']);

defineOptions({ name: 'LeadZapsignCard' });
const { t } = useI18n();

// ZapSign (item 21, fluxo A): botão gera contrato+procuração pré-preenchidos
// e devolve o link de assinatura — nada é enviado ao cliente automaticamente.
// Fallback local da resposta: se o websocket estiver caído, o lead da store não
// recebe o zapsign novo e o botão continuaria armado — 2º clique = 2º contrato.
const zapsignLocal = ref(null);
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

// Troca de lead: zera o link local e re-chuta o modelo pela tese do lead novo.
watch(
  () => props.lead?.id,
  () => {
    zapsignLocal.value = null;
    templateId.value = guessTemplate(templates.value);
  }
);

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
  <div data-testid="zapsign-card" :class="CARTAO">
    <div class="flex items-center gap-2">
      <span class="i-lucide-pen-line size-3.5 shrink-0 text-n-slate-10" />
      <p :class="TITULO">
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
      <select
        v-model="templateId"
        :aria-label="$t('RAMON.ZAPSIGN.TEMPLATE_LABEL')"
        data-testid="zapsign-template"
        :disabled="templatesError || !templates.length"
        class="mt-2"
        :class="SELECT"
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
          class="inline-flex"
        >
          <Button
            sm
            tabindex="-1"
            :class="ACAO"
            :label="$t('RAMON.ZAPSIGN.OPEN')"
          />
        </a>
        <Button
          data-testid="zapsign-copy"
          sm
          faded
          slate
          :label="$t('RAMON.ZAPSIGN.COPY')"
          @click="copyLink"
        />
      </template>
      <Button
        v-else
        data-testid="zapsign-generate"
        sm
        :class="ACAO"
        :disabled="loading || missing.length > 0 || !templateId"
        :label="
          loading
            ? $t('RAMON.ZAPSIGN.GENERATING')
            : $t('RAMON.ZAPSIGN.GENERATE_SHORT')
        "
        @click="generate"
      />
      <Button
        v-if="missing.length"
        data-testid="zapsign-complete-data"
        sm
        faded
        slate
        :label="$t('RAMON.ZAPSIGN.COMPLETE_DATA')"
        @click="emit('completeData')"
      />
    </div>
  </div>
</template>
