<script setup>
// Detalhe de um cliente do Painel do Cliente (lado do escritório): e-mail,
// recado por processo, documento pra assinatura e envios. Seções (SECAO),
// nunca cartão dentro do cartão da lista.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PortalClientesAPI from 'dashboard/api/portalClientes';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  AVISO,
  CAMPO,
  CHIP,
  ROTULO,
  SECAO,
  SELECT,
  TEXTAREA,
  TITULO,
  TOM,
} from '../../helpers/ui';

const props = defineProps({
  cliente: { type: Object, required: true },
  templates: { type: Array, default: () => [] },
});
const emit = defineEmits(['atualizar', 'recarregar']);

const { t } = useI18n();
const recados = ref({ ...props.cliente.recados });
const emailEdit = ref(props.cliente.email || '');
const aviso = ref('');
const templateId = ref(null);
const nomeDocumento = ref('Procuração');
const enviandoAssinatura = ref(false);

const erro = e =>
  useAlert(e?.response?.data?.error || t('RAMON.PORTAL_CLIENTES.ACTION_ERROR'));

const avisarSalvo = () => {
  aviso.value = t('RAMON.PORTAL_CLIENTES.SAVED');
  setTimeout(() => {
    aviso.value = '';
  }, 2000);
};

const enviarAssinatura = async () => {
  const hoje = new Date().toLocaleDateString('pt-BR', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  });
  enviandoAssinatura.value = true;
  try {
    await PortalClientesAPI.assinatura(props.cliente.id, {
      template_id: templateId.value,
      nome: nomeDocumento.value,
      variaveis: {
        '{{nome}}': props.cliente.nome,
        '{{CPF}}': props.cliente.cpf,
        '{{email}}': props.cliente.email,
        '{{data de hoje}}': hoje,
      },
    });
    const { data } = await PortalClientesAPI.show(props.cliente.id);
    emit('atualizar', data);
  } catch (e) {
    erro(e);
  } finally {
    enviandoAssinatura.value = false;
  }
};

const salvarRecados = async () => {
  try {
    await PortalClientesAPI.update(props.cliente.id, {
      recados: recados.value,
    });
    avisarSalvo();
  } catch (e) {
    erro(e);
  }
};

const salvarEmail = async () => {
  try {
    const { data } = await PortalClientesAPI.update(props.cliente.id, {
      email: emailEdit.value.trim(),
    });
    emit('atualizar', data);
    avisarSalvo();
    emit('recarregar');
  } catch (e) {
    erro(e);
  }
};

// status espelha o ZapSign: pendente | signed | refused.
const TOM_ASSINATURA = { signed: TOM.teal, refused: TOM.ruby };

const dataCurta = iso =>
  iso ? new Date(iso).toLocaleDateString('pt-BR') : '—';
</script>

<template>
  <div class="mt-3 flex flex-col gap-4 ps-5">
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

    <p v-if="!cliente.processos.length" :class="[AVISO, TOM.slate]" class="m-0">
      {{ t('RAMON.PORTAL_CLIENTES.NO_LAWSUITS') }}
    </p>
    <div
      v-for="p in cliente.processos"
      :key="p.id"
      class="flex flex-col gap-2"
      :class="SECAO"
    >
      <div class="flex flex-wrap items-center gap-2 text-xs">
        <span class="font-mono text-n-slate-12">{{ p.numero }}</span>
        <span class="text-n-slate-10">· {{ p.tipo }} · {{ p.etapa }}</span>
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
      <span v-if="aviso" class="text-xs text-n-teal-11">{{ aviso }}</span>
    </div>

    <div class="flex flex-col gap-2" :class="SECAO">
      <div class="flex flex-wrap items-center gap-2">
        <select v-model="templateId" :class="SELECT" class="!w-auto">
          <option :value="null">
            {{ t('RAMON.PORTAL_CLIENTES.TEMPLATE') }}
          </option>
          <option v-for="tpl in templates" :key="tpl.token" :value="tpl.token">
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
      <template v-if="cliente.assinaturas && cliente.assinaturas.length">
        <p :class="TITULO" class="m-0 mt-1">
          {{ t('RAMON.PORTAL_CLIENTES.SIGNATURES_LIST') }}
        </p>
        <ul class="m-0 flex list-none flex-col gap-1 p-0 text-xs">
          <li
            v-for="a in cliente.assinaturas"
            :key="a.id"
            class="flex items-center gap-2"
          >
            <span class="text-n-slate-12">{{ a.nome }}</span>
            <span :class="[CHIP, TOM_ASSINATURA[a.status] || TOM.amber]">
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
      v-if="cliente.envios.length"
      class="m-0 flex list-none flex-col gap-1 p-0 text-xs text-n-slate-11"
      :class="SECAO"
    >
      <li v-for="e in cliente.envios" :key="e.id">
        <span class="font-mono text-n-slate-10">{{
          dataCurta(e.created_at)
        }}</span>
        · {{ e.item }} · {{ t('RAMON.PORTAL_CLIENTES.DRIVE') }}
        <span :class="e.drive_file_id ? 'text-n-teal-11' : 'text-n-slate-10'">{{
          e.drive_file_id ? '✓' : '…'
        }}</span>
      </li>
    </ul>
  </div>
</template>
