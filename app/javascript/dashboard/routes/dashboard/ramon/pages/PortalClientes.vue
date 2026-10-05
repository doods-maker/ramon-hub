<script setup>
// app/javascript/dashboard/routes/dashboard/ramon/pages/PortalClientes.vue
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PortalClientesAPI from 'dashboard/api/portalClientes';
import RamonCalculosAPI from 'dashboard/api/ramonCalculos';
import LeadsAPI from 'dashboard/api/leads';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import PortalClienteDetalhe from '../components/portal/PortalClienteDetalhe.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { AVISO, CAMPO, CARTAO, CHIP, SECAO, TITULO, TOM } from '../helpers/ui';
import { FILTROS, filtrarClientes } from '../helpers/portalClientes';

defineOptions({ name: 'RamonPortalClientes' });

const { t } = useI18n();
const route = useRoute();
const clientes = ref([]);
const metricas = ref(null); // funil do piloto + documentos
const isLoading = ref(false);
const hasError = ref(false);
const busca = ref('');
const resultados = ref([]);
const candidato = ref(null); // cliente do ADVBOX escolhido pra convidar
const emailConvite = ref('');
// Resposta de convite/senha nova: { nome, senha_provisoria, email: { status, para },
// mensagem, whatsapp_url } — aparece uma vez, o hub não guarda a senha em claro.
const senhaGerada = ref(null);
const emailConfigurado = ref(true);
// O que quem está logado pode fazer (o backend decide; aqui só esconde botão).
const permissoes = ref({ gerir_acesso: false, excluir: false });
const aberto = ref(null); // detalhe expandido
const templates = ref([]); // modelos do ZapSign, carregados na 1ª expansão de linha
// Janela de confirmação aberta: { title, message, confirmLabel, confirmColor, acao }.
const confirmacao = ref(null);

const erro = e =>
  useAlert(e?.response?.data?.error || t('RAMON.PORTAL_CLIENTES.ACTION_ERROR'));

const confirmar = async () => {
  const { acao } = confirmacao.value;
  confirmacao.value = null;
  await acao();
};

const carregar = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await PortalClientesAPI.get();
    clientes.value = data.payload;
    metricas.value = data.metricas;
    emailConfigurado.value = data.email_configurado !== false;
    permissoes.value = data.permissoes || permissoes.value;
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
    senhaGerada.value = data;
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

// Senha nova derruba a do cliente: sempre passa pela janela de confirmação.
const reenviar = c => {
  confirmacao.value = {
    title: t('RAMON.PORTAL_CLIENTES.CONFIRM_NEW_PASSWORD_TITLE', {
      nome: c.nome,
    }),
    message:
      c.email && emailConfigurado.value
        ? t('RAMON.PORTAL_CLIENTES.CONFIRM_NEW_PASSWORD_EMAIL', {
            email: c.email,
          })
        : t('RAMON.PORTAL_CLIENTES.CONFIRM_NEW_PASSWORD'),
    confirmLabel: t('RAMON.PORTAL_CLIENTES.CONFIRM_NEW_PASSWORD_BTN'),
    confirmColor: 'blue',
    acao: async () => {
      try {
        const { data } = await PortalClientesAPI.convidar(c.id);
        senhaGerada.value = data;
        resultados.value = [];
        await carregar();
      } catch (e) {
        erro(e);
      }
    },
  };
};

// Resultado do ADVBOX que já tem acesso ao painel (convidado) — vira "Nova senha".
const comAcesso = c =>
  clientes.value.find(x => x.advbox_customer_id === c.id && x.convidado_em);

// id do cliente cujo detalhe não carregou (mostra erro + tentar de novo na linha).
const erroDetalhe = ref(null);

const carregarDetalhe = async id => {
  erroDetalhe.value = null;
  try {
    const { data } = await PortalClientesAPI.show(id);
    aberto.value = data;
  } catch {
    aberto.value = null;
    erroDetalhe.value = id;
  }
};

const abrir = async id => {
  if (aberto.value?.id === id || erroDetalhe.value === id) {
    aberto.value = null;
    erroDetalhe.value = null;
    return;
  }
  await carregarDetalhe(id);
  if (!templates.value.length) {
    try {
      const resp = await LeadsAPI.zapsignTemplates();
      templates.value = resp.data;
    } catch {
      templates.value = [];
    }
  }
};

const excluir = c => {
  confirmacao.value = {
    title: t('RAMON.PORTAL_CLIENTES.DELETE_TITLE', { nome: c.nome }),
    message: t('RAMON.PORTAL_CLIENTES.DELETE_CONFIRM'),
    confirmLabel: t('RAMON.PORTAL_CLIENTES.DELETE'),
    confirmColor: 'ruby',
    acao: async () => {
      try {
        await PortalClientesAPI.delete(c.id);
        if (aberto.value?.id === c.id) aberto.value = null;
        await carregar();
      } catch (e) {
        erro(e);
      }
    },
  };
};

const reativar = async c => {
  try {
    await PortalClientesAPI.reativar(c.id);
    await carregar();
  } catch (e) {
    erro(e);
  }
};

// Suspender não apaga nada: só tira o acesso (e derruba as sessões abertas).
const suspender = c => {
  confirmacao.value = {
    title: t('RAMON.PORTAL_CLIENTES.SUSPEND_TITLE', { nome: c.nome }),
    message: t('RAMON.PORTAL_CLIENTES.SUSPEND_CONFIRM'),
    confirmLabel: t('RAMON.PORTAL_CLIENTES.SUSPEND'),
    confirmColor: 'ruby',
    acao: async () => {
      try {
        await PortalClientesAPI.suspender(c.id);
        await carregar();
      } catch (e) {
        erro(e);
      }
    },
  };
};

const copiar = async (texto, ok) => {
  try {
    await navigator.clipboard.writeText(texto);
    useAlert(t(ok));
  } catch {
    useAlert(t('RAMON.PORTAL_CLIENTES.ACTION_ERROR'));
  }
};

// Linha "E-mail enviado para X / NÃO enviado (motivo)" da senha recém-gerada.
const EMAIL_STATUS = {
  enviado: 'RAMON.PORTAL_CLIENTES.EMAIL_SENT',
  sem_email: 'RAMON.PORTAL_CLIENTES.EMAIL_NOT_SENT_NO_EMAIL',
  sem_servidor: 'RAMON.PORTAL_CLIENTES.EMAIL_NOT_SENT_NO_SERVER',
};

const abrirWhatsapp = () =>
  window.open(senhaGerada.value.whatsapp_url, '_blank', 'noopener');

const METRICAS = [
  'convidados',
  'entraram',
  'voltaram',
  'enviaram',
  'assinaram',
  'docs_pedidos',
  'docs_enviados',
];

const dataCurta = iso =>
  iso ? new Date(iso).toLocaleDateString('pt-BR') : '—';

// Lista: busca por nome/CPF + um filtro rápido por vez.
const filtroBusca = ref('');
const filtro = ref(null);
const visiveis = computed(() =>
  filtrarClientes(clientes.value, {
    busca: filtroBusca.value,
    filtro: filtro.value,
  })
);
const contagem = chave =>
  filtrarClientes(clientes.value, { filtro: chave }).length;
const alternarFiltro = chave => {
  filtro.value = filtro.value === chave ? null : chave;
};

// Deep link …/ramon/portal?cliente=<id> (painel do lead): já abre o cliente.
onMounted(async () => {
  await carregar();
  const id = Number(route.query?.cliente);
  if (id && clientes.value.some(c => c.id === id)) await abrir(id);
});
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
              <span v-if="comAcesso(c)" class="ms-2" :class="[CHIP, TOM.blue]">
                {{ t('RAMON.PORTAL_CLIENTES.HAS_ACCESS') }}
              </span>
            </span>
            <Button
              v-if="comAcesso(c)"
              link
              xs
              :label="t('RAMON.PORTAL_CLIENTES.NEW_PASSWORD')"
              @click="reenviar(comAcesso(c))"
            />
            <Button
              v-else
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

      <!-- Senha provisória: aparece uma vez, com o caminho de entrega -->
      <div
        v-if="senhaGerada"
        data-testid="portal-senha"
        class="flex flex-col gap-2 !py-3"
        :class="[AVISO, TOM.amber]"
      >
        <div class="flex flex-wrap items-center gap-3">
          <span class="text-sm text-n-slate-12">
            {{
              t('RAMON.PORTAL_CLIENTES.TEMP_PASSWORD', {
                nome: senhaGerada.nome,
              })
            }}
            <strong class="ms-1 font-mono text-lg tracking-widest">{{
              senhaGerada.senha_provisoria
            }}</strong>
          </span>
          <Button
            xs
            icon="i-lucide-copy"
            :label="t('RAMON.PORTAL_CLIENTES.COPY')"
            @click="
              copiar(
                senhaGerada.senha_provisoria,
                'RAMON.PORTAL_CLIENTES.COPIED'
              )
            "
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
        <p
          v-if="senhaGerada.email"
          data-testid="portal-email-status"
          class="m-0 flex items-center gap-1.5"
          :class="
            senhaGerada.email.status === 'enviado'
              ? 'text-n-teal-11'
              : 'font-medium text-n-ruby-11'
          "
        >
          <span
            class="size-3.5 shrink-0"
            :class="
              senhaGerada.email.status === 'enviado'
                ? 'i-lucide-mail-check'
                : 'i-lucide-mail-x'
            "
          />
          {{
            t(EMAIL_STATUS[senhaGerada.email.status], {
              email: senhaGerada.email.para,
            })
          }}
        </p>
        <template v-if="senhaGerada.mensagem">
          <p class="m-0 mt-1 text-n-slate-11" :class="TITULO">
            {{ t('RAMON.PORTAL_CLIENTES.READY_MESSAGE') }}
          </p>
          <p
            data-testid="portal-mensagem"
            class="m-0 whitespace-pre-line border-s-2 border-n-amber-9/40 ps-3 text-n-slate-12"
          >
            {{ senhaGerada.mensagem }}
          </p>
          <div class="flex flex-wrap gap-2">
            <Button
              xs
              faded
              slate
              icon="i-lucide-copy"
              :label="t('RAMON.PORTAL_CLIENTES.COPY_MESSAGE')"
              @click="
                copiar(
                  senhaGerada.mensagem,
                  'RAMON.PORTAL_CLIENTES.MESSAGE_COPIED'
                )
              "
            />
            <Button
              v-if="senhaGerada.whatsapp_url"
              xs
              faded
              teal
              icon="i-ri-whatsapp-line"
              :label="t('RAMON.PORTAL_CLIENTES.OPEN_WHATSAPP')"
              @click="abrirWhatsapp"
            />
          </div>
        </template>
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
      <template v-else>
        <!-- Busca + filtros rápidos (um por vez) -->
        <div
          class="flex flex-wrap items-center gap-2"
          data-testid="portal-filtros"
        >
          <input
            v-model="filtroBusca"
            type="search"
            :class="CAMPO"
            class="!w-64"
            :placeholder="t('RAMON.PORTAL_CLIENTES.FILTER_SEARCH')"
          />
          <button
            v-for="chave in Object.keys(FILTROS)"
            :key="chave"
            type="button"
            class="transition-none"
            :class="[
              CHIP,
              filtro === chave
                ? `${TOM.blue} ring-1 ring-n-blue-9/40`
                : TOM.slate,
            ]"
            @click="alternarFiltro(chave)"
          >
            {{ t(`RAMON.PORTAL_CLIENTES.FILTERS.${chave.toUpperCase()}`) }}
            <span class="font-mono">{{ contagem(chave) }}</span>
          </button>
        </div>
        <p
          v-if="!visiveis.length"
          :class="CARTAO"
          class="m-0 py-6 text-center text-sm text-n-slate-10"
        >
          {{ t('RAMON.PORTAL_CLIENTES.FILTER_EMPTY') }}
        </p>
        <ul
          v-else
          class="m-0 flex list-none flex-col divide-y divide-n-weak !p-0"
          :class="CARTAO"
        >
          <li v-for="c in visiveis" :key="c.id" class="px-4 py-3 text-sm">
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
                  <span v-if="c.suspenso_em" :class="[CHIP, TOM.ruby]">
                    {{ t('RAMON.PORTAL_CLIENTES.SUSPENDED') }}
                  </span>
                  <span
                    v-else
                    :class="[CHIP, c.convidado_em ? TOM.blue : TOM.slate]"
                  >
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
              <!-- Último acesso em coluna própria -->
              <span class="flex w-24 shrink-0 flex-col items-end">
                <span class="text-[10px] text-n-slate-10">{{
                  t('RAMON.PORTAL_CLIENTES.LAST_ACCESS')
                }}</span>
                <span class="font-mono text-xs text-n-slate-12">{{
                  dataCurta(c.ultimo_acesso_em)
                }}</span>
              </span>
              <span
                class="w-16 shrink-0 whitespace-nowrap text-right text-xs text-n-slate-11"
              >
                <span class="font-mono">{{ c.envios_count }}</span>
                {{ t('RAMON.PORTAL_CLIENTES.UPLOADS') }}
              </span>
              <!-- 1º convite: todo agente; senha nova/suspender: gerir_acesso; excluir: admin.
                   Largura fixa: a coluna "Último acesso" fica alinhada entre as linhas. -->
              <div class="flex w-[19rem] shrink-0 justify-end gap-4">
                <Button
                  v-if="
                    !c.suspenso_em &&
                    (!c.convidado_em || permissoes.gerir_acesso)
                  "
                  link
                  xs
                  :label="t('RAMON.PORTAL_CLIENTES.REINVITE')"
                  @click="reenviar(c)"
                />
                <template v-if="permissoes.gerir_acesso && c.convidado_em">
                  <Button
                    v-if="c.suspenso_em"
                    link
                    xs
                    :label="t('RAMON.PORTAL_CLIENTES.REACTIVATE')"
                    @click="reativar(c)"
                  />
                  <Button
                    v-else
                    link
                    xs
                    ruby
                    :label="t('RAMON.PORTAL_CLIENTES.SUSPEND')"
                    @click="suspender(c)"
                  />
                </template>
                <Button
                  v-if="permissoes.excluir"
                  link
                  xs
                  ruby
                  :label="t('RAMON.PORTAL_CLIENTES.DELETE')"
                  @click="excluir(c)"
                />
              </div>
            </div>

            <div
              v-if="erroDetalhe === c.id"
              data-testid="portal-detalhe-erro"
              class="mt-3 flex items-center gap-3 ps-5 text-xs"
            >
              <span class="text-n-ruby-11">{{
                t('RAMON.PORTAL_CLIENTES.DETAIL_ERROR')
              }}</span>
              <Button
                link
                xs
                :label="t('RAMON.LEAD_PANEL.RETRY')"
                @click="carregarDetalhe(c.id)"
              />
            </div>
            <PortalClienteDetalhe
              v-if="aberto && aberto.id === c.id"
              :key="aberto.id"
              :cliente="aberto"
              :templates="templates"
              @atualizar="aberto = $event"
              @recarregar="carregar"
            />
          </li>
        </ul>
      </template>
    </div>

    <ConfirmModal
      v-if="confirmacao"
      :title="confirmacao.title"
      :message="confirmacao.message"
      :confirm-label="confirmacao.confirmLabel"
      :confirm-color="confirmacao.confirmColor"
      @confirm="confirmar"
      @cancel="confirmacao = null"
    />
  </div>
</template>
