<script setup>
// Detalhe de um cliente do Painel do Cliente (lado do escritório): e-mail,
// recado por processo, documento pra assinatura e envios. Seções (SECAO),
// nunca cartão dentro do cartão da lista.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PortalClientesAPI from 'dashboard/api/portalClientes';
import Button from 'dashboard/components-next/button/Button.vue';
import ConfirmModal from '../ConfirmModal.vue';
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
// O que já está no ar pro cliente: a prévia aparece quando o texto mudou.
const recadosSalvos = ref({ ...props.cliente.recados });
const recadoMudou = id =>
  (recados.value[id] || '').trim() !== (recadosSalvos.value[id] || '').trim();
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
    recadosSalvos.value = { ...recados.value };
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
const dataCurta = iso =>
  iso ? new Date(iso).toLocaleDateString('pt-BR') : '—';

// status do ZapSign em português; assinado mostra a data.
const TOM_ASSINATURA = {
  pendente: TOM.amber,
  signed: TOM.teal,
  refused: TOM.ruby,
  cancelado: TOM.slate,
};
const ROTULO_ASSINATURA = {
  pendente: 'RAMON.PORTAL_CLIENTES.SIGNATURE_STATUS.PENDENTE',
  signed: 'RAMON.PORTAL_CLIENTES.SIGNATURE_STATUS.SIGNED',
  refused: 'RAMON.PORTAL_CLIENTES.SIGNATURE_STATUS.REFUSED',
  cancelado: 'RAMON.PORTAL_CLIENTES.SIGNATURE_STATUS.CANCELADO',
};
const statusAssinatura = a =>
  ROTULO_ASSINATURA[a.status] ? t(ROTULO_ASSINATURA[a.status]) : a.status;

// Cancelar documento pendente: confirma, cancela no ZapSign e some do "assinar" do cliente.
const cancelando = ref(null);
const cancelarAssinatura = async () => {
  const a = cancelando.value;
  cancelando.value = null;
  try {
    const { data } = await PortalClientesAPI.cancelarAssinatura(
      props.cliente.id,
      a.id
    );
    emit('atualizar', data);
  } catch (e) {
    erro(e);
  }
};

const faltam = p => (p.documentos || []).filter(d => !d.enviado).length;

const dataHora = iso =>
  new Date(iso).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
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
        <span v-if="faltam(p)" :class="[CHIP, TOM.amber]">
          <span class="font-mono">{{ faltam(p) }}</span>
          {{ t('RAMON.PORTAL_CLIENTES.PENDING_DOCS') }}
        </span>
      </div>
      <p class="m-0 text-xs text-n-slate-11" data-testid="portal-cliente-ve">
        {{ t('RAMON.PORTAL_CLIENTES.CLIENT_SEES') }}
        <span class="font-medium text-n-slate-12">{{ p.cliente_ve }}</span>
      </p>
      <p
        v-if="p.etapa_interna"
        data-testid="portal-etapa-interna"
        :class="[AVISO, TOM.amber]"
        class="m-0"
      >
        {{
          t('RAMON.PORTAL_CLIENTES.INTERNAL_STAGE', { titulo: p.cliente_ve })
        }}
      </p>
      <!-- Cada documento pedido: falta / enviado em dd/mm (mesma regra do portal) -->
      <ul
        v-if="p.documentos && p.documentos.length"
        data-testid="portal-documentos"
        class="m-0 flex list-none flex-col gap-1 p-0 text-xs"
      >
        <li
          v-for="(d, i) in p.documentos"
          :key="`${d.item}-${i}`"
          class="flex items-center gap-2"
        >
          <span
            class="size-3.5 shrink-0"
            :class="
              d.enviado
                ? 'i-lucide-circle-check text-n-teal-11'
                : 'i-lucide-circle-dashed text-n-amber-11'
            "
          />
          <span class="text-n-slate-12">{{ d.item }}</span>
          <span v-if="d.enviado" :class="[CHIP, TOM.teal]">
            {{ t('RAMON.PORTAL_CLIENTES.DOC_SENT_ON') }}
            <span class="font-mono">{{ dataCurta(d.enviado_em) }}</span>
          </span>
          <span v-else :class="[CHIP, TOM.amber]">
            {{ t('RAMON.PORTAL_CLIENTES.DOC_MISSING') }}
          </span>
        </li>
      </ul>
      <label :class="ROTULO">
        {{ t('RAMON.PORTAL_CLIENTES.RECADO') }}
        <textarea v-model="recados[p.id]" rows="2" :class="TEXTAREA" />
      </label>
      <!-- Prévia do recado como o cliente vai ver (só quando ainda não foi salvo) -->
      <div
        v-if="recadoMudou(p.id) && (recados[p.id] || '').trim()"
        data-testid="portal-recado-previa"
        :class="[AVISO, TOM.slate]"
      >
        <p :class="TITULO" class="m-0 mb-1">
          {{ t('RAMON.PORTAL_CLIENTES.RECADO_PREVIEW') }}
        </p>
        <p class="m-0 text-xs font-semibold text-n-slate-12">
          {{ t('RAMON.PORTAL_CLIENTES.RECADO_PREVIEW_HEADING') }}
        </p>
        <p class="m-0 whitespace-pre-line text-sm text-n-slate-12">
          {{ recados[p.id].trim() }}
        </p>
      </div>
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
            <span :class="[CHIP, TOM_ASSINATURA[a.status] || TOM.slate]">
              {{ statusAssinatura(a) }}
              <span
                v-if="a.status === 'signed' && a.assinado_em"
                class="font-mono"
              >
                {{ dataCurta(a.assinado_em) }}
              </span>
            </span>
            <span class="font-mono text-n-slate-10">{{
              dataCurta(a.created_at)
            }}</span>
            <Button
              v-if="a.status === 'pendente'"
              link
              xs
              ruby
              class="ms-auto"
              :label="t('RAMON.PORTAL_CLIENTES.CANCEL_DOCUMENT')"
              @click="cancelando = a"
            />
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
        · {{ e.item }} ·
        <a
          v-if="e.drive_url"
          :href="e.drive_url"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-0.5 text-xs text-n-blue-11 hover:underline"
        >
          {{ t('RAMON.PORTAL_CLIENTES.DRIVE_OPEN') }}
          <span class="i-lucide-external-link size-3" />
        </a>
        <span v-else class="text-n-slate-10">{{
          t('RAMON.PORTAL_CLIENTES.DRIVE_PENDING')
        }}</span>
      </li>
    </ul>

    <!-- Histórico do hub: quem fez o quê neste cliente -->
    <div v-if="cliente.eventos && cliente.eventos.length" :class="SECAO">
      <p :class="TITULO" class="m-0 mb-2">
        {{ t('RAMON.PORTAL_CLIENTES.HISTORY') }}
      </p>
      <ul
        data-testid="portal-historico"
        class="m-0 flex list-none flex-col gap-1 p-0 text-xs text-n-slate-11"
      >
        <li v-for="ev in cliente.eventos" :key="ev.id">
          <span class="font-mono text-n-slate-10">{{
            dataHora(ev.created_at)
          }}</span>
          · <span class="text-n-slate-12">{{ ev.user_name || '—' }}</span>
          {{ t(`RAMON.PORTAL_CLIENTES.EVENTS.${ev.acao.toUpperCase()}`) }}
          <template v-if="ev.detalhe">· {{ ev.detalhe }}</template>
        </li>
      </ul>
    </div>
    <ConfirmModal
      v-if="cancelando"
      :title="
        t('RAMON.PORTAL_CLIENTES.CANCEL_DOCUMENT_TITLE', {
          nome: cancelando.nome,
        })
      "
      :message="t('RAMON.PORTAL_CLIENTES.CANCEL_DOCUMENT_CONFIRM')"
      :confirm-label="t('RAMON.PORTAL_CLIENTES.CANCEL_DOCUMENT')"
      @confirm="cancelarAssinatura"
      @cancel="cancelando = null"
    />
  </div>
</template>
