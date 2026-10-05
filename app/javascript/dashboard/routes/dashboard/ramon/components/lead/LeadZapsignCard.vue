<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadsAPI from 'dashboard/api/leads';
import Button from 'dashboard/components-next/button/Button.vue';
import { CARTAO, TITULO, SELECT, CAMPO, ROTULO, SECAO } from '../../helpers/ui';

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

// "Dados do contrato": o que o contrato usa e o painel não edita em outro
// lugar. Grava no contato; a prévia (o que sairia em branco) vem do backend —
// mesma conta do ZapsignContractService, sem espelhar as 12 variáveis aqui.
// Valor = texto que vai no contrato, por isso a opção mostra o próprio valor.
const ESTADOS_CIVIS = [
  'solteiro(a)',
  'casado(a)',
  'divorciado(a)',
  'separado(a)',
  'viúvo(a)',
  'em união estável',
];
const CAMPOS = [
  'cep',
  'rua',
  'numero',
  'complemento',
  'bairro',
  'cidade',
  'uf',
  'estado_civil',
  'profissao',
  'email',
];
const form = ref({});
const salvo = ref('');
const preview = ref(null);
const dirty = computed(() => JSON.stringify(form.value) !== salvo.value);
// estado civil vindo da colheita ("casado") fora da lista não some do select
const estadosCivis = computed(() => {
  const atual = form.value.estado_civil;
  return atual && !ESTADOS_CIVIS.includes(atual)
    ? [atual, ...ESTADOS_CIVIS]
    : ESTADOS_CIVIS;
});

const aplicarPreview = data => {
  preview.value = data;
  form.value = Object.fromEntries(
    CAMPOS.map(campo => [campo, data.dados?.[campo] || ''])
  );
  salvo.value = JSON.stringify(form.value);
};

const carregarPreview = async () => {
  try {
    const { data } = await LeadsAPI.zapsignPreview(props.lead.id);
    aplicarPreview(data);
  } catch (error) {
    preview.value = null;
  }
};

const salvando = ref(false);
const salvarDados = async () => {
  salvando.value = true;
  try {
    const { cep, rua, numero, complemento, bairro, cidade, uf, ...resto } =
      form.value;
    const { data } = await LeadsAPI.saveZapsignDados(props.lead.id, {
      ...resto,
      endereco: { cep, rua, numero, complemento, bairro, cidade, uf },
    });
    aplicarPreview(data);
    return true;
  } catch (error) {
    useAlert(error.response?.data?.error || t('RAMON.ZAPSIGN.SAVE_ERROR'));
    return false;
  } finally {
    salvando.value = false;
  }
};

// CEP com 8 dígitos → rua/bairro/cidade/UF pelo ViaCEP (via backend).
// Número e complemento ficam com o closer.
const buscarCep = async () => {
  const cep = (form.value.cep || '').replace(/\D/g, '');
  if (cep.length !== 8) return;
  try {
    const { data } = await LeadsAPI.zapsignCep(cep);
    form.value = { ...form.value, ...data };
  } catch (error) {
    useAlert(
      error.response?.status === 404
        ? t('RAMON.ZAPSIGN.CEP_NOT_FOUND')
        : t('RAMON.ZAPSIGN.CEP_ERROR')
    );
  }
};

// Troca de lead: zera o link local e re-chuta o modelo pela tese do lead novo.
watch(
  () => props.lead?.id,
  () => {
    zapsignLocal.value = null;
    templateId.value = guessTemplate(templates.value);
    carregarPreview();
  }
);

onMounted(async () => {
  carregarPreview();
  try {
    const { data } = await LeadsAPI.zapsignTemplates();
    templates.value = data;
    templateId.value = guessTemplate(data);
  } catch (error) {
    templatesError.value = true;
  }
});

// Antes de gerar: a prévia do backend. Depois: o que de fato saiu em branco.
const missing = computed(() => {
  const lista = zapsign.value
    ? zapsign.value.faltando
    : preview.value?.faltando;
  return (lista || []).map(f => f.replace(/[{}]/g, ''));
});
// Nome/CPF/telefone não estão no formulário: "Completar dados" leva ao Resumo.
const faltaForaDoForm = computed(() =>
  missing.value.some(campo => ['nome', 'CPF', 'telefone'].includes(campo))
);

const loading = ref(false);
const generate = async () => {
  if (loading.value) return;
  loading.value = true;
  try {
    // edição não salva vai junto: o contrato sai com o que está na tela
    if (dirty.value && !(await salvarDados())) return;
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

    <template v-if="!zapsign?.sign_url">
      <form
        data-testid="zapsign-form"
        class="mt-3 grid grid-cols-6 gap-2"
        :class="SECAO"
        @submit.prevent="salvarDados"
      >
        <p class="col-span-6" :class="TITULO">
          {{ $t('RAMON.ZAPSIGN.FORM_TITLE') }}
        </p>
        <label class="col-span-2" :class="ROTULO">
          {{ $t('RAMON.ZAPSIGN.CAMPOS.CEP') }}
          <input
            v-model="form.cep"
            data-testid="zapsign-cep"
            inputmode="numeric"
            maxlength="9"
            :class="CAMPO"
            @input="buscarCep"
          />
        </label>
        <label class="col-span-4" :class="ROTULO">
          {{ $t('RAMON.ZAPSIGN.CAMPOS.RUA') }}
          <input v-model="form.rua" :class="CAMPO" />
        </label>
        <label class="col-span-2" :class="ROTULO">
          {{ $t('RAMON.ZAPSIGN.CAMPOS.NUMERO') }}
          <input v-model="form.numero" :class="CAMPO" />
        </label>
        <label class="col-span-4" :class="ROTULO">
          {{ $t('RAMON.ZAPSIGN.CAMPOS.COMPLEMENTO') }}
          <input
            v-model="form.complemento"
            :placeholder="$t('RAMON.ZAPSIGN.OPTIONAL')"
            :class="CAMPO"
          />
        </label>
        <label class="col-span-3" :class="ROTULO">
          {{ $t('RAMON.ZAPSIGN.CAMPOS.BAIRRO') }}
          <input v-model="form.bairro" :class="CAMPO" />
        </label>
        <label class="col-span-2" :class="ROTULO">
          {{ $t('RAMON.ZAPSIGN.CAMPOS.CIDADE') }}
          <input v-model="form.cidade" :class="CAMPO" />
        </label>
        <label class="col-span-1" :class="ROTULO">
          {{ $t('RAMON.ZAPSIGN.CAMPOS.UF') }}
          <input v-model="form.uf" maxlength="2" :class="CAMPO" />
        </label>
        <label class="col-span-3" :class="ROTULO">
          {{ $t('RAMON.ZAPSIGN.CAMPOS.ESTADO_CIVIL') }}
          <select v-model="form.estado_civil" :class="SELECT">
            <option value="" />
            <option v-for="ec in estadosCivis" :key="ec" :value="ec">
              {{ ec }}
            </option>
          </select>
        </label>
        <label class="col-span-3" :class="ROTULO">
          {{ $t('RAMON.ZAPSIGN.CAMPOS.PROFISSAO') }}
          <input v-model="form.profissao" :class="CAMPO" />
        </label>
        <label class="col-span-6" :class="ROTULO">
          {{ $t('RAMON.ZAPSIGN.CAMPOS.EMAIL') }}
          <input v-model="form.email" type="email" :class="CAMPO" />
        </label>
        <div class="col-span-6 flex justify-end">
          <Button
            data-testid="zapsign-save"
            type="submit"
            sm
            faded
            slate
            :disabled="!dirty || salvando"
            :label="$t('RAMON.ZAPSIGN.SAVE_DATA')"
          />
        </div>
      </form>

      <p
        v-if="missing.length"
        data-testid="zapsign-blanks"
        class="mt-3 text-[11.5px] leading-relaxed text-n-slate-11"
      >
        {{ $t('RAMON.ZAPSIGN.BLANKS_HINT') }}
        <span class="text-n-amber-11">{{ missing.join(', ') }}</span>
      </p>
      <p
        v-else-if="preview"
        class="mt-3 text-[11.5px] leading-relaxed text-n-teal-11"
      >
        {{ $t('RAMON.ZAPSIGN.NO_BLANKS') }}
      </p>

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
    <template v-else>
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
      <p class="mt-2 text-[11px] text-n-slate-10">
        {{
          $t('RAMON.ZAPSIGN.TEMPLATE_USED', {
            name: zapsign.template_name || '—',
          })
        }}
      </p>
    </template>

    <div class="flex flex-wrap items-center gap-1.5 mt-2.5">
      <template v-if="zapsign?.sign_url">
        <a
          :href="zapsign.sign_url"
          target="_blank"
          rel="noopener noreferrer"
          data-testid="zapsign-link"
          class="inline-flex"
        >
          <Button sm tabindex="-1" :label="$t('RAMON.ZAPSIGN.OPEN')" />
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
        :disabled="loading || !templateId"
        :label="
          loading
            ? $t('RAMON.ZAPSIGN.GENERATING')
            : $t('RAMON.ZAPSIGN.GENERATE_SHORT')
        "
        @click="generate"
      />
      <Button
        v-if="faltaForaDoForm"
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
