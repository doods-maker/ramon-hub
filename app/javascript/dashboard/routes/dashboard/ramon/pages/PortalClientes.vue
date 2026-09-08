<script setup>
// app/javascript/dashboard/routes/dashboard/ramon/pages/PortalClientes.vue
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PortalClientesAPI from 'dashboard/api/portalClientes';
import RamonCalculosAPI from 'dashboard/api/ramonCalculos';
import LeadsAPI from 'dashboard/api/leads';
import RamonPageHeader from '../components/RamonPageHeader.vue';

defineOptions({ name: 'RamonPortalClientes' });

const { t } = useI18n();
const clientes = ref([]);
const isLoading = ref(false);
const hasError = ref(false);
const busca = ref('');
const resultados = ref([]);
const candidato = ref(null); // cliente do ADVBOX escolhido pra convidar
const emailConvite = ref('');
const aberto = ref(null); // detalhe expandido
const recados = ref({});
const aviso = ref('');
const templates = ref([]); // modelos do ZapSign, carregados na 1ª expansão de linha
const templateId = ref(null);
const nomeDocumento = ref('Procuração');
const enviandoAssinatura = ref(false);

const carregar = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await PortalClientesAPI.get();
    clientes.value = data.payload;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const buscar = async () => {
  if (busca.value.trim().length < 3) return;
  try {
    const { data } = await RamonCalculosAPI.advboxCustomers(busca.value.trim());
    resultados.value = data.payload;
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('RAMON.PORTAL_CLIENTES.ACTION_ERROR')
    );
  }
};

const escolher = c => {
  candidato.value = c;
  emailConvite.value = (c.email || '').toLowerCase();
};

const convidar = async () => {
  const c = candidato.value;
  try {
    await PortalClientesAPI.create({
      advbox_customer_id: c.id,
      nome: c.name,
      cpf: c.identification,
      email: emailConvite.value,
    });
    candidato.value = null;
    resultados.value = [];
    busca.value = '';
    await carregar();
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('RAMON.PORTAL_CLIENTES.ACTION_ERROR')
    );
  }
};

const reenviar = async id => {
  try {
    await PortalClientesAPI.convidar(id);
    await carregar();
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('RAMON.PORTAL_CLIENTES.ACTION_ERROR')
    );
  }
};

const abrir = async id => {
  if (aberto.value?.id === id) {
    aberto.value = null;
    return;
  }
  const { data } = await PortalClientesAPI.show(id);
  aberto.value = data;
  recados.value = { ...data.recados };
  templateId.value = null;
  nomeDocumento.value = 'Procuração';
  if (!templates.value.length) {
    try {
      const resp = await LeadsAPI.zapsignTemplates();
      templates.value = resp.data;
    } catch {
      templates.value = [];
    }
  }
};

const enviarAssinatura = async () => {
  const hoje = new Date().toLocaleDateString('pt-BR', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  });
  enviandoAssinatura.value = true;
  try {
    await PortalClientesAPI.assinatura(aberto.value.id, {
      template_id: templateId.value,
      nome: nomeDocumento.value,
      variaveis: {
        '{{nome}}': aberto.value.nome,
        '{{CPF}}': aberto.value.cpf,
        '{{email}}': aberto.value.email,
        '{{data de hoje}}': hoje,
      },
    });
    const { data: atualizado } = await PortalClientesAPI.show(aberto.value.id);
    aberto.value = atualizado;
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('RAMON.PORTAL_CLIENTES.ACTION_ERROR')
    );
  } finally {
    enviandoAssinatura.value = false;
  }
};

const salvarRecados = async () => {
  try {
    await PortalClientesAPI.update(aberto.value.id, { recados: recados.value });
    aviso.value = t('RAMON.PORTAL_CLIENTES.SAVED');
    setTimeout(() => {
      aviso.value = '';
    }, 2000);
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('RAMON.PORTAL_CLIENTES.ACTION_ERROR')
    );
  }
};

const dataCurta = iso =>
  iso ? new Date(iso).toLocaleDateString('pt-BR') : '—';

onMounted(carregar);
</script>

<template>
  <div class="flex h-full w-full flex-col overflow-y-auto p-8">
    <RamonPageHeader
      :title="t('RAMON.PORTAL_CLIENTES.TITLE')"
      :subtitle="t('RAMON.PORTAL_CLIENTES.SUBTITLE')"
    />

    <div class="mb-6 rounded-xl border border-n-weak bg-n-solid-1 p-4">
      <div class="flex gap-2">
        <input
          v-model="busca"
          type="search"
          class="flex-1 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
          :placeholder="t('RAMON.PORTAL_CLIENTES.SEARCH')"
          @keyup.enter="buscar"
        />
        <button
          type="button"
          class="rounded-lg bg-n-iris-9 px-3 py-2 text-sm text-white"
          @click="buscar"
        >
          {{ t('RAMON.PORTAL_CLIENTES.SEARCH_BTN') }}
        </button>
      </div>
      <ul
        v-if="resultados.length"
        class="mt-3 flex flex-col divide-y divide-n-weak"
      >
        <li
          v-for="c in resultados"
          :key="c.id"
          class="flex items-center justify-between py-2 text-sm"
        >
          <span>
            {{ c.name }}
            <span class="text-n-slate-11">{{ c.identification }}</span>
          </span>
          <button
            type="button"
            class="text-n-iris-11 hover:underline"
            @click="escolher(c)"
          >
            {{ t('RAMON.PORTAL_CLIENTES.INVITE') }}
          </button>
        </li>
      </ul>
      <div v-if="candidato" class="mt-3 flex items-center gap-2">
        <span class="text-sm font-medium">{{ candidato.name }}</span>
        <input
          v-model="emailConvite"
          type="email"
          class="flex-1 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
          :placeholder="t('RAMON.PORTAL_CLIENTES.EMAIL')"
        />
        <button
          type="button"
          class="rounded-lg bg-n-iris-9 px-3 py-2 text-sm text-white"
          :disabled="!emailConvite"
          @click="convidar"
        >
          {{ t('RAMON.PORTAL_CLIENTES.INVITE') }}
        </button>
      </div>
    </div>

    <div v-if="isLoading" class="h-12 animate-pulse rounded-lg bg-n-solid-2" />
    <p v-else-if="hasError" class="text-sm text-n-ruby-11">
      {{ t('RAMON.PORTAL_CLIENTES.LOAD_ERROR') }}
    </p>
    <p v-else-if="!clientes.length" class="text-sm text-n-slate-11">
      {{ t('RAMON.PORTAL_CLIENTES.EMPTY') }}
    </p>
    <ul
      v-else
      class="flex flex-col divide-y divide-n-weak rounded-xl border border-n-weak bg-n-solid-1"
    >
      <li v-for="c in clientes" :key="c.id" class="px-4 py-3 text-sm">
        <div class="flex items-center justify-between gap-4">
          <button
            type="button"
            class="min-w-0 flex-1 truncate text-start font-medium"
            @click="abrir(c.id)"
          >
            {{ c.nome }}
            <span class="font-normal text-n-slate-11">{{ c.email }}</span>
          </button>
          <span class="text-xs text-n-slate-11">
            {{
              c.convidado_em
                ? t('RAMON.PORTAL_CLIENTES.INVITED')
                : t('RAMON.PORTAL_CLIENTES.NOT_INVITED')
            }}
            ·
            {{
              c.termos_aceitos_em ? t('RAMON.PORTAL_CLIENTES.TERMS_OK') : '—'
            }}
            · {{ t('RAMON.PORTAL_CLIENTES.SYNCED') }}
            {{ dataCurta(c.sincronizado_em) }}
          </span>
          <span class="text-xs"
            >{{ c.envios_count }} {{ t('RAMON.PORTAL_CLIENTES.UPLOADS') }}</span
          >
          <button
            type="button"
            class="text-xs text-n-iris-11 hover:underline"
            @click="reenviar(c.id)"
          >
            {{ t('RAMON.PORTAL_CLIENTES.REINVITE') }}
          </button>
        </div>
        <div
          v-if="aberto && aberto.id === c.id"
          class="mt-3 flex flex-col gap-3"
        >
          <div
            v-for="p in aberto.processos"
            :key="p.id"
            class="rounded-lg border border-n-weak p-3"
          >
            <p class="text-xs text-n-slate-11">
              {{ p.numero }} · {{ p.tipo }} · {{ p.etapa }}
            </p>
            <p v-if="p.docs_pendentes.length" class="text-xs">
              {{ p.docs_pendentes.length }}
              {{ t('RAMON.PORTAL_CLIENTES.PENDING_DOCS') }}
            </p>
            <label class="mt-2 block text-xs">{{
              t('RAMON.PORTAL_CLIENTES.RECADO')
            }}</label>
            <textarea
              v-model="recados[p.id]"
              rows="2"
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1 text-sm"
            />
          </div>
          <div class="flex items-center gap-3">
            <button
              type="button"
              class="rounded-lg bg-n-iris-9 px-3 py-1.5 text-xs text-white"
              @click="salvarRecados"
            >
              {{ t('RAMON.PORTAL_CLIENTES.RECADO_SAVE') }}
            </button>
            <span v-if="aviso" class="text-xs text-n-teal-11">{{ aviso }}</span>
          </div>
          <div class="flex flex-col gap-2 rounded-lg border border-n-weak p-3">
            <div class="flex flex-wrap items-center gap-2">
              <select
                v-model="templateId"
                class="rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1 text-xs"
              >
                <option :value="null">
                  {{ t('RAMON.PORTAL_CLIENTES.TEMPLATE') }}
                </option>
                <option
                  v-for="tpl in templates"
                  :key="tpl.token"
                  :value="tpl.token"
                >
                  {{ tpl.name }}
                </option>
              </select>
              <input
                v-model="nomeDocumento"
                type="text"
                class="rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1 text-xs"
                :placeholder="t('RAMON.PORTAL_CLIENTES.DOC_NAME')"
              />
              <button
                type="button"
                class="rounded-lg bg-n-iris-9 px-3 py-1.5 text-xs text-white disabled:opacity-50"
                :disabled="!templateId || enviandoAssinatura"
                @click="enviarAssinatura"
              >
                {{ t('RAMON.PORTAL_CLIENTES.SEND_SIGNATURE') }}
              </button>
            </div>
            <template v-if="aberto.assinaturas && aberto.assinaturas.length">
              <p class="text-xs font-medium">
                {{ t('RAMON.PORTAL_CLIENTES.SIGNATURES_LIST') }}
              </p>
              <ul class="text-xs text-n-slate-11">
                <li v-for="a in aberto.assinaturas" :key="a.id">
                  {{ a.nome }} · {{ a.status }} · {{ dataCurta(a.created_at) }}
                </li>
              </ul>
            </template>
          </div>
          <ul v-if="aberto.envios.length" class="text-xs text-n-slate-11">
            <li v-for="e in aberto.envios" :key="e.id">
              {{ dataCurta(e.created_at) }} · {{ e.item }} ·
              {{ t('RAMON.PORTAL_CLIENTES.DRIVE') }}
              {{ e.drive_file_id ? '✓' : '…' }}
            </li>
          </ul>
        </div>
      </li>
    </ul>
  </div>
</template>
