<script setup>
// app/javascript/dashboard/routes/dashboard/ramon/pages/PortalClientes.vue
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PortalClientesAPI from 'dashboard/api/portalClientes';
import RamonCalculosAPI from 'dashboard/api/ramonCalculos';
import LeadsAPI from 'dashboard/api/leads';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  AVISO,
  CAMPO,
  CARTAO,
  CHIP,
  ROTULO,
  SECAO,
  SELECT,
  TEXTAREA,
  TITULO,
  TOM,
} from '../helpers/ui';

defineOptions({ name: 'RamonPortalClientes' });

const { t } = useI18n();
const clientes = ref([]);
const metricas = ref(null); // funil do piloto + documentos
const isLoading = ref(false);
const hasError = ref(false);
const busca = ref('');
const resultados = ref([]);
const candidato = ref(null); // cliente do ADVBOX escolhido pra convidar
const emailConvite = ref('');
const senhaGerada = ref(null); // { nome, senha } — aparece uma vez, o hub não guarda em claro
const aberto = ref(null); // detalhe expandido
const recados = ref({});
const emailEdit = ref('');
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
    metricas.value = data.metricas;
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
    const { data } = await PortalClientesAPI.create({
      advbox_customer_id: c.id,
      nome: c.name,
      cpf: c.identification,
      email: emailConvite.value,
      telefone: c.cellphone,
    });
    senhaGerada.value = { nome: data.nome, senha: data.senha_provisoria };
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
    const { data } = await PortalClientesAPI.convidar(id);
    senhaGerada.value = { nome: data.nome, senha: data.senha_provisoria };
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
  emailEdit.value = data.email || '';
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

const salvarEmail = async () => {
  try {
    const { data } = await PortalClientesAPI.update(aberto.value.id, {
      email: emailEdit.value.trim(),
    });
    aberto.value = data;
    aviso.value = t('RAMON.PORTAL_CLIENTES.SAVED');
    setTimeout(() => {
      aviso.value = '';
    }, 2000);
    await carregar();
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('RAMON.PORTAL_CLIENTES.ACTION_ERROR')
    );
  }
};

const excluir = async c => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(t('RAMON.PORTAL_CLIENTES.DELETE_CONFIRM', { nome: c.nome }))
  )
    return;
  try {
    await PortalClientesAPI.delete(c.id);
    if (aberto.value?.id === c.id) aberto.value = null;
    await carregar();
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('RAMON.PORTAL_CLIENTES.ACTION_ERROR')
    );
  }
};

const copiarSenha = async () => {
  try {
    await navigator.clipboard.writeText(senhaGerada.value.senha);
    useAlert(t('RAMON.PORTAL_CLIENTES.COPIED'));
  } catch {
    useAlert(t('RAMON.PORTAL_CLIENTES.ACTION_ERROR'));
  }
};

const METRICAS = [
  'convidados',
  'entraram',
  'voltaram',
  'enviaram',
  'assinaram',
  'docs_pedidos',
  'docs_enviados',
];

// status espelha o ZapSign: pendente | signed | refused.
const TOM_ASSINATURA = { signed: TOM.teal, refused: TOM.ruby };

const dataCurta = iso =>
  iso ? new Date(iso).toLocaleDateString('pt-BR') : '—';

onMounted(carregar);
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-background p-4 sm:p-8">
    <div class="mx-auto flex w-full max-w-5xl flex-col gap-5">
      <RamonPageHeader
        class="!mb-0"
        :title="t('RAMON.PORTAL_CLIENTES.TITLE')"
        :subtitle="t('RAMON.PORTAL_CLIENTES.SUBTITLE')"
      />

      <!-- Convidar: busca no ADVBOX → escolhe → e-mail → convida -->
      <div :class="CARTAO">
        <div class="flex gap-2">
          <input
            v-model="busca"
            type="search"
            :class="CAMPO"
            class="flex-1"
            :placeholder="t('RAMON.PORTAL_CLIENTES.SEARCH')"
            @keyup.enter="buscar"
          />
          <Button
            sm
            icon="i-lucide-search"
            :label="t('RAMON.PORTAL_CLIENTES.SEARCH_BTN')"
            @click="buscar"
          />
        </div>
        <ul
          v-if="resultados.length"
          class="m-0 mt-3 flex list-none flex-col divide-y divide-n-weak border-t border-n-weak p-0"
        >
          <li
            v-for="c in resultados"
            :key="c.id"
            class="flex items-center justify-between gap-3 py-1.5 text-sm"
          >
            <span class="min-w-0 truncate text-n-slate-12">
              {{ c.name }}
              <span class="ms-1 font-mono text-xs text-n-slate-10">{{
                c.identification
              }}</span>
            </span>
            <Button
              link
              xs
              :label="t('RAMON.PORTAL_CLIENTES.INVITE')"
              @click="escolher(c)"
            />
          </li>
        </ul>
        <div
          v-if="candidato"
          class="mt-3 flex items-center gap-2"
          :class="SECAO"
        >
          <span class="text-sm font-medium text-n-slate-12">{{
            candidato.name
          }}</span>
          <input
            v-model="emailConvite"
            type="email"
            :class="CAMPO"
            class="flex-1"
            :placeholder="t('RAMON.PORTAL_CLIENTES.EMAIL')"
          />
          <Button
            sm
            icon="i-lucide-send"
            :label="t('RAMON.PORTAL_CLIENTES.INVITE')"
            @click="convidar"
          />
        </div>
      </div>

      <!-- Senha provisória: aparece uma vez -->
      <div
        v-if="senhaGerada"
        class="flex flex-wrap items-center gap-3 !py-3"
        :class="[AVISO, TOM.amber]"
      >
        <span class="text-sm text-n-slate-12">
          {{
            t('RAMON.PORTAL_CLIENTES.TEMP_PASSWORD', { nome: senhaGerada.nome })
          }}
          <strong class="ms-1 font-mono text-lg tracking-widest">{{
            senhaGerada.senha
          }}</strong>
        </span>
        <Button
          xs
          icon="i-lucide-copy"
          :label="t('RAMON.PORTAL_CLIENTES.COPY')"
          @click="copiarSenha"
        />
        <span>{{ t('RAMON.PORTAL_CLIENTES.TEMP_PASSWORD_HINT') }}</span>
        <Button
          link
          xs
          slate
          class="ms-auto"
          :label="t('RAMON.PORTAL_CLIENTES.DISMISS')"
          @click="senhaGerada = null"
        />
      </div>

      <!-- Funil do piloto + documentos -->
      <div
        v-if="metricas"
        class="grid grid-cols-2 gap-2.5 sm:grid-cols-4 lg:grid-cols-7"
      >
        <div v-for="chave in METRICAS" :key="chave" :class="CARTAO">
          <p class="font-mono text-xl font-medium tabular-nums text-n-slate-12">
            {{ metricas[chave] }}
          </p>
          <p class="mt-0.5 text-[11px] leading-snug text-n-slate-10">
            {{ t(`RAMON.PORTAL_CLIENTES.METRICS.${chave.toUpperCase()}`) }}
          </p>
        </div>
      </div>

      <div
        v-if="isLoading"
        class="h-32 animate-pulse rounded-xl bg-n-alpha-2"
      />
      <p v-else-if="hasError" class="text-sm text-n-ruby-11">
        {{ t('RAMON.PORTAL_CLIENTES.LOAD_ERROR') }}
      </p>
      <p
        v-else-if="!clientes.length"
        :class="CARTAO"
        class="py-6 text-center text-sm text-n-slate-10"
      >
        {{ t('RAMON.PORTAL_CLIENTES.EMPTY') }}
      </p>
      <ul
        v-else
        class="m-0 flex list-none flex-col divide-y divide-n-weak !p-0"
        :class="CARTAO"
      >
        <li v-for="c in clientes" :key="c.id" class="px-4 py-3 text-sm">
          <div class="flex items-center gap-4">
            <button
              type="button"
              class="flex min-w-0 flex-1 flex-col items-start gap-1 text-start"
              @click="abrir(c.id)"
            >
              <span class="flex min-w-0 max-w-full items-center gap-2">
                <span
                  class="size-3.5 shrink-0 text-n-slate-10"
                  :class="
                    aberto && aberto.id === c.id
                      ? 'i-lucide-chevron-down'
                      : 'i-lucide-chevron-right'
                  "
                />
                <span class="truncate font-medium text-n-slate-12">{{
                  c.nome
                }}</span>
                <span :class="[CHIP, c.convidado_em ? TOM.blue : TOM.slate]">
                  {{
                    c.convidado_em
                      ? t('RAMON.PORTAL_CLIENTES.INVITED')
                      : t('RAMON.PORTAL_CLIENTES.NOT_INVITED')
                  }}
                </span>
                <span v-if="c.termos_aceitos_em" :class="[CHIP, TOM.teal]">
                  {{ t('RAMON.PORTAL_CLIENTES.TERMS_OK') }}
                </span>
              </span>
              <!-- cada trecho "rótulo valor" não quebra no meio -->
              <span class="ps-5 text-xs text-n-slate-10">
                <span class="font-mono">{{ c.cpf }}</span>
                <template v-if="c.email"> · {{ c.email }}</template>
                ·
                <span class="whitespace-nowrap">
                  {{ t('RAMON.PORTAL_CLIENTES.LAST_ACCESS') }}
                  <span class="font-mono">{{
                    dataCurta(c.ultimo_acesso_em)
                  }}</span>
                </span>
                ·
                <span class="whitespace-nowrap">{{
                  t('RAMON.PORTAL_CLIENTES.ACCESS_DAYS', { n: c.dias_acesso })
                }}</span>
                ·
                <span class="whitespace-nowrap">
                  {{ t('RAMON.PORTAL_CLIENTES.SYNCED') }}
                  <span class="font-mono">{{
                    dataCurta(c.sincronizado_em)
                  }}</span>
                </span>
              </span>
            </button>
            <span class="whitespace-nowrap text-xs text-n-slate-11">
              <span class="font-mono">{{ c.envios_count }}</span>
              {{ t('RAMON.PORTAL_CLIENTES.UPLOADS') }}
            </span>
            <Button
              link
              xs
              :label="t('RAMON.PORTAL_CLIENTES.REINVITE')"
              @click="reenviar(c.id)"
            />
            <Button
              link
              xs
              ruby
              :label="t('RAMON.PORTAL_CLIENTES.DELETE')"
              @click="excluir(c)"
            />
          </div>

          <!-- Detalhe: seções (sem cartão dentro de cartão) -->
          <div
            v-if="aberto && aberto.id === c.id"
            class="mt-3 flex flex-col gap-4 ps-5"
          >
            <div class="flex flex-wrap items-end gap-2" :class="SECAO">
              <label :class="ROTULO" class="min-w-64 flex-1">
                {{ t('RAMON.PORTAL_CLIENTES.EMAIL_EDIT') }}
                <input
                  v-model="emailEdit"
                  type="email"
                  :class="CAMPO"
                  :placeholder="t('RAMON.PORTAL_CLIENTES.EMAIL')"
                />
              </label>
              <Button
                sm
                faded
                slate
                :label="t('RAMON.PORTAL_CLIENTES.EMAIL_SAVE')"
                @click="salvarEmail"
              />
            </div>

            <p
              v-if="!aberto.processos.length"
              :class="[AVISO, TOM.slate]"
              class="m-0"
            >
              {{ t('RAMON.PORTAL_CLIENTES.NO_LAWSUITS') }}
            </p>
            <div
              v-for="p in aberto.processos"
              :key="p.id"
              class="flex flex-col gap-2"
              :class="SECAO"
            >
              <div class="flex flex-wrap items-center gap-2 text-xs">
                <span class="font-mono text-n-slate-12">{{ p.numero }}</span>
                <span class="text-n-slate-10"
                  >· {{ p.tipo }} · {{ p.etapa }}</span
                >
                <span v-if="p.docs_pendentes.length" :class="[CHIP, TOM.amber]">
                  <span class="font-mono">{{ p.docs_pendentes.length }}</span>
                  {{ t('RAMON.PORTAL_CLIENTES.PENDING_DOCS') }}
                </span>
              </div>
              <label :class="ROTULO">
                {{ t('RAMON.PORTAL_CLIENTES.RECADO') }}
                <textarea v-model="recados[p.id]" rows="2" :class="TEXTAREA" />
              </label>
            </div>
            <div class="flex items-center gap-3">
              <Button
                sm
                :label="t('RAMON.PORTAL_CLIENTES.RECADO_SAVE')"
                @click="salvarRecados"
              />
              <span v-if="aviso" class="text-xs text-n-teal-11">{{
                aviso
              }}</span>
            </div>

            <div class="flex flex-col gap-2" :class="SECAO">
              <div class="flex flex-wrap items-center gap-2">
                <select v-model="templateId" :class="SELECT" class="!w-auto">
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
                  :class="CAMPO"
                  class="!w-56"
                  :placeholder="t('RAMON.PORTAL_CLIENTES.DOC_NAME')"
                />
                <Button
                  sm
                  icon="i-lucide-signature"
                  :label="t('RAMON.PORTAL_CLIENTES.SEND_SIGNATURE')"
                  :disabled="!templateId || enviandoAssinatura"
                  @click="enviarAssinatura"
                />
              </div>
              <template v-if="aberto.assinaturas && aberto.assinaturas.length">
                <p :class="TITULO" class="m-0 mt-1">
                  {{ t('RAMON.PORTAL_CLIENTES.SIGNATURES_LIST') }}
                </p>
                <ul class="m-0 flex list-none flex-col gap-1 p-0 text-xs">
                  <li
                    v-for="a in aberto.assinaturas"
                    :key="a.id"
                    class="flex items-center gap-2"
                  >
                    <span class="text-n-slate-12">{{ a.nome }}</span>
                    <span
                      :class="[CHIP, TOM_ASSINATURA[a.status] || TOM.amber]"
                    >
                      {{ a.status }}
                    </span>
                    <span class="font-mono text-n-slate-10">{{
                      dataCurta(a.created_at)
                    }}</span>
                  </li>
                </ul>
              </template>
            </div>

            <ul
              v-if="aberto.envios.length"
              class="m-0 flex list-none flex-col gap-1 p-0 text-xs text-n-slate-11"
              :class="SECAO"
            >
              <li v-for="e in aberto.envios" :key="e.id">
                <span class="font-mono text-n-slate-10">{{
                  dataCurta(e.created_at)
                }}</span>
                · {{ e.item }} · {{ t('RAMON.PORTAL_CLIENTES.DRIVE') }}
                <span
                  :class="
                    e.drive_file_id ? 'text-n-teal-11' : 'text-n-slate-10'
                  "
                  >{{ e.drive_file_id ? '✓' : '…' }}</span
                >
              </li>
            </ul>
          </div>
        </li>
      </ul>
    </div>
  </div>
</template>
