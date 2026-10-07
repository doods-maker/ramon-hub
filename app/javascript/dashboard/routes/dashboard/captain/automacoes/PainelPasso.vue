<script setup>
// Painel direito do editor (mockup .painel): config do passo selecionado.
// Sempre emite config NOVA (o editor troca no node do Vue Flow).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  AVISO,
  CAMPO,
  ROTULO,
  SELECT,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import {
  PAPEIS,
  PASSOS,
  ROTINAS,
  TIPOS_ATIVIDADE,
  TIPOS_TAREFA,
  UNIDADES,
  gatilhoInfo,
} from './fluxo';
import CampoTexto from './CampoTexto.vue';
import ConfigAcoesChatwoot from './ConfigAcoesChatwoot.vue';
import ConfigCasos from './ConfigCasos.vue';
import ConfigAdvbox from './ConfigAdvbox.vue';
import ConfigCondicoes from './ConfigCondicoes.vue';
import ConfigGatilho from './ConfigGatilho.vue';
import ConfigIa from './ConfigIa.vue';
import JanelaHorario from './JanelaHorario.vue';
import ListaMarcar from './ListaMarcar.vue';

const props = defineProps({
  no: { type: Object, required: true },
  erros: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:config', 'duplicar', 'excluir']);
const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const etapas = useMapGetter('leadConfig/getStages');
const pessoas = useMapGetter('agents/getAgents');

const tipo = computed(() => props.no.data.tipo);
const config = computed(() => props.no.data.config || {});
const info = computed(() => PASSOS[tipo.value] || PASSOS.parar);
const gatilho = computed(() => tipo.value === 'gatilho');
const icone = computed(() =>
  gatilho.value
    ? gatilhoInfo(config.value.tipo)?.icone || info.value.icone
    : info.value.icone
);
const opcoesPessoas = computed(() =>
  pessoas.value.map(p => ({ id: p.id, nome: p.name }))
);
// esperar: um tempo (do passo anterior), até o horário comercial (B4.2: com a janela do passo), antes da reunião
// (B4.1: conta para trás) ou a partir da criação da conversa (B4.2: um tempo ou o SLA da caixa)
const modoEspera = computed(() => {
  const c = config.value;
  if (c.ate === 'horario_comercial') return 'horario';
  if (c.desde === 'conversa')
    return c.prazo === 'sla_caixa' ? 'sla' : 'conversa';
  return c.antes_de === 'reuniao' ? 'reuniao' : 'tempo';
});
const OPCOES_ESPERA = [
  { modo: 'tempo', rotulo: 'ESPERAR_TEMPO', ajuda: 'ESPERAR_AJUDA' },
  { modo: 'horario', rotulo: 'ESPERAR_HORARIO', ajuda: 'ESPERAR_AJUDA' },
  {
    modo: 'reuniao',
    rotulo: 'ESPERAR_REUNIAO',
    ajuda: 'ESPERAR_REUNIAO_AJUDA',
  },
  {
    modo: 'conversa',
    rotulo: 'ESPERAR_CONVERSA',
    ajuda: 'ESPERAR_CONVERSA_AJUDA',
  },
  { modo: 'sla', rotulo: 'ESPERAR_SLA', ajuda: 'ESPERAR_CONVERSA_AJUDA' },
];
const CONFIG_ESPERA = {
  tempo: { quantidade: 1, unidade: 'dias' },
  horario: { ate: 'horario_comercial' },
  reuniao: { antes_de: 'reuniao', quantidade: 1, unidade: 'horas' },
  conversa: { desde: 'conversa', quantidade: 60, unidade: 'minutos' },
  sla: { desde: 'conversa', prazo: 'sla_caixa' },
};
const ajudaEspera = computed(
  () => OPCOES_ESPERA.find(o => o.modo === modoEspera.value).ajuda
);
const pedeTempo = computed(
  () => !['horario', 'sla'].includes(modoEspera.value)
);
// sino: pessoas marcadas (padrão), Closer e SDR do lead, a conta toda (B4.1), SDR ou gestores, gestores (B4.2)
const PARA_SINO = [
  { valor: '', rotulo: 'PARA_PESSOAS' },
  { valor: 'closer_e_sdr', rotulo: 'PARA_CLOSER_SDR' },
  { valor: 'conta', rotulo: 'PARA_CONTA' },
  { valor: 'sdr_ou_gestores', rotulo: 'PARA_SDR_GESTORES' },
  { valor: 'gestores', rotulo: 'PARA_GESTORES' },
];

const muda = (chave, valor) =>
  emit('update:config', { ...config.value, [chave]: valor });
const numeroOuNada = v => (v === '' ? null : Number(v));
const trocaEspera = modo =>
  emit('update:config', {
    rotulo: config.value.rotulo,
    ...CONFIG_ESPERA[modo],
  });
// opção liga/desliga: desligada some do JSON
const marca = (chave, ligada, valor = true) =>
  muda(chave, ligada ? valor : undefined);
// mover para etapa de perda (PR #216): motivo da lista da conta, "Outro" (texto livre) ou vazio = automático
const motivosPerda = useMapGetter('leadConfig/getLostReasons');
const OUTRO = '__outro';
const outroMotivo = ref(false);
const etapaPerda = computed(
  () => etapas.value.find(e => e.id === config.value.etapa_id)?.is_lost
);
const motivoEscolhido = computed(() => {
  const motivo = config.value.motivo;
  const daLista = motivosPerda.value.some(r => r.name === motivo);
  return outroMotivo.value || (motivo && !daLista) ? OUTRO : motivo || '';
});
const escolheMotivo = valor => {
  outroMotivo.value = valor === OUTRO;
  muda('motivo', outroMotivo.value || !valor ? undefined : valor);
};
</script>

<template>
  <div class="flex h-full min-h-0 flex-col">
    <div class="flex items-center gap-2.5 border-b border-n-weak px-4 py-3.5">
      <span
        class="grid size-7 place-items-center rounded-lg"
        :class="TOM[info.tom]"
      >
        <i :class="icone" class="size-4" />
      </span>
      <div>
        <b class="block text-sm font-semibold text-n-slate-12">
          {{ t(`${K}.PASSOS.${tipo}`, tipo) }}
        </b>
        <span class="text-xs text-n-slate-10">
          {{ t(`${K}.CABECALHO.${tipo}`, tipo) }} ·
          {{ t(`${K}.NO.PASSO_N`, { id: no.id }) }}
        </span>
      </div>
    </div>

    <div class="flex flex-1 flex-col gap-4 overflow-y-auto px-4 py-3.5">
      <div v-if="erros.length" :class="[AVISO, TOM.ruby]">
        <p v-for="e in erros" :key="e">{{ e }}</p>
      </div>
      <div
        v-if="info.rascunho"
        data-testid="painel-aviso-rascunho"
        :class="[AVISO, TOM.amber]"
        class="flex gap-2.5"
      >
        <i class="i-lucide-shield-check mt-0.5 size-4 shrink-0" />
        <span class="text-n-slate-12">{{
          t(`${K}.PAINEL.AVISO_RASCUNHO`)
        }}</span>
      </div>

      <label v-if="!gatilho" :class="ROTULO">
        {{ t(`${K}.PAINEL.ROTULO`) }}
        <input
          :class="CAMPO"
          :value="config.rotulo || ''"
          @input="muda('rotulo', $event.target.value)"
        />
      </label>

      <ConfigGatilho
        v-if="gatilho"
        :config="config"
        @update:config="c => emit('update:config', c)"
      />
      <ConfigCondicoes
        v-else-if="tipo === 'se'"
        :config="config"
        @update:config="c => emit('update:config', c)"
      />
      <ConfigCasos
        v-else-if="tipo === 'escolha'"
        :config="config"
        @update:config="c => emit('update:config', c)"
      />
      <ConfigAcoesChatwoot
        v-else-if="tipo === 'acao_chatwoot'"
        :config="config"
        @update:config="c => emit('update:config', c)"
      />
      <ConfigIa
        v-else-if="
          ['perguntar_ia', 'rascunho_ia', 'rodar_skill'].includes(tipo)
        "
        :key="`${no.id}-${tipo}`"
        :tipo="tipo"
        :config="config"
        @update:config="c => emit('update:config', c)"
      />
      <ConfigAdvbox
        v-else-if="tipo === 'advbox'"
        :key="no.id"
        :config="config"
        @update:config="c => emit('update:config', c)"
      />

      <CampoTexto
        v-else-if="tipo === 'nota_privada'"
        :rotulo="t(`${K}.PAINEL.TEXTO`)"
        :model-value="config.texto || ''"
        @update:model-value="v => muda('texto', v)"
      />

      <template v-else-if="tipo === 'rascunho_texto'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.ONDE_RASCUNHO`) }}
          <select
            data-testid="rascunho-onde"
            :class="SELECT"
            :value="config.onde || ''"
            @change="muda('onde', $event.target.value || undefined)"
          >
            <option value="">{{ t(`${K}.PAINEL.ONDE_CONVERSA`) }}</option>
            <option value="notas_do_lead">
              {{ t(`${K}.PAINEL.ONDE_NOTAS`) }}
            </option>
          </select>
        </label>
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.TITULO_RASCUNHO`) }}
          <input
            data-testid="rascunho-titulo"
            :class="CAMPO"
            :value="config.titulo || ''"
            @input="muda('titulo', $event.target.value)"
          />
        </label>
        <CampoTexto
          :rotulo="t(`${K}.PAINEL.TEXTO`)"
          :model-value="config.texto || ''"
          @update:model-value="v => muda('texto', v)"
        />
      </template>

      <template v-else-if="tipo === 'registrar_atividade'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.TIPO_ATIVIDADE`) }}
          <select
            data-testid="atividade-tipo"
            :class="SELECT"
            :value="config.tipo || 'fluxo'"
            @change="muda('tipo', $event.target.value)"
          >
            <option v-for="k in TIPOS_ATIVIDADE" :key="k" :value="k">
              {{ t(`${K}.TIPOS_ATIVIDADE.${k}`) }}
            </option>
          </select>
        </label>
        <CampoTexto
          v-if="config.tipo === 'meeting_rescheduled'"
          :rotulo="t(`${K}.PAINEL.DE`)"
          :linhas="2"
          :model-value="config.de || ''"
          @update:model-value="v => muda('de', v)"
        />
        <CampoTexto
          :rotulo="t(`${K}.PAINEL.TEXTO`)"
          :model-value="config.texto || ''"
          @update:model-value="v => muda('texto', v)"
        />
      </template>

      <template v-else-if="tipo === 'mover_etapa'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.ETAPA`) }}
          <select
            :class="SELECT"
            :value="config.etapa_id ?? ''"
            @change="muda('etapa_id', Number($event.target.value))"
          >
            <option value="" disabled>
              {{ t(`${K}.PAINEL.ESCOLHA_ETAPA`) }}
            </option>
            <option v-for="e in etapas" :key="e.id" :value="e.id">
              {{ e.name }}
            </option>
          </select>
        </label>
        <template v-if="etapaPerda">
          <label :class="ROTULO">
            {{ t(`${K}.PAINEL.MOTIVO_PERDA`) }}
            <select
              data-testid="motivo-perda"
              :class="SELECT"
              :value="motivoEscolhido"
              @change="escolheMotivo($event.target.value)"
            >
              <option value="">{{ t(`${K}.PAINEL.MOTIVO_AUTOMATICO`) }}</option>
              <option v-for="m in motivosPerda" :key="m.id" :value="m.name">
                {{ m.name }}
              </option>
              <option :value="OUTRO">
                {{ t(`${K}.PAINEL.MOTIVO_OUTRO`) }}
              </option>
            </select>
          </label>
          <input
            v-if="motivoEscolhido === OUTRO"
            data-testid="motivo-outro"
            :class="CAMPO"
            :placeholder="t(`${K}.PAINEL.MOTIVO_OUTRO_PLACEHOLDER`)"
            :value="config.motivo || ''"
            @input="muda('motivo', $event.target.value)"
          />
        </template>
        <label class="flex items-center gap-2 text-[13px] text-n-slate-12">
          <input
            data-testid="so-para-frente"
            type="checkbox"
            class="reset-base"
            :checked="!!config.so_para_frente"
            @change="marca('so_para_frente', $event.target.checked)"
          />
          {{ t(`${K}.PAINEL.SO_PARA_FRENTE`) }}
        </label>
      </template>

      <template v-else-if="tipo === 'criar_tarefa'">
        <CampoTexto
          :rotulo="t(`${K}.PAINEL.TITULO_TAREFA`)"
          :linhas="2"
          :model-value="config.titulo || ''"
          @update:model-value="v => muda('titulo', v)"
        />
        <label class="flex items-center gap-2 text-[13px] text-n-slate-12">
          <input
            data-testid="tarefa-da-reuniao"
            type="checkbox"
            class="reset-base"
            :checked="config.prazo === 'reuniao'"
            @change="marca('prazo', $event.target.checked, 'reuniao')"
          />
          {{ t(`${K}.PAINEL.TAREFA_DA_REUNIAO`) }}
        </label>
        <div class="grid grid-cols-2 gap-2">
          <label :class="ROTULO">
            {{ t(`${K}.PAINEL.TIPO_TAREFA`) }}
            <select
              :class="SELECT"
              :value="config.tipo || 'other'"
              @change="muda('tipo', $event.target.value)"
            >
              <option v-for="k in TIPOS_TAREFA" :key="k" :value="k">
                {{ t(`${K}.TIPOS_TAREFA.${k}`) }}
              </option>
            </select>
          </label>
          <label v-if="config.prazo !== 'reuniao'" :class="ROTULO">
            {{ t(`${K}.PAINEL.PRAZO`) }}
            <input
              :class="CAMPO"
              type="number"
              min="0"
              :value="config.prazo_dias ?? 1"
              @change="muda('prazo_dias', Number($event.target.value))"
            />
          </label>
        </div>
        <label v-if="config.prazo !== 'reuniao'" :class="ROTULO">
          {{ t(`${K}.PAINEL.RESPONSAVEL`) }}
          <select
            :class="SELECT"
            :value="config.responsavel_id ?? ''"
            @change="muda('responsavel_id', numeroOuNada($event.target.value))"
          >
            <option value="">{{ t(`${K}.PAINEL.RESPONSAVEL_DO_LEAD`) }}</option>
            <option v-for="p in pessoas" :key="p.id" :value="p.id">
              {{ p.name }}
            </option>
          </select>
        </label>
      </template>

      <template v-else-if="tipo === 'avisar_sino'">
        <CampoTexto
          :rotulo="t(`${K}.PAINEL.TEXTO`)"
          :linhas="2"
          :model-value="config.texto || ''"
          @update:model-value="v => muda('texto', v)"
        />
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.QUEM_RECEBE`) }}
          <select
            data-testid="sino-para"
            :class="SELECT"
            :value="config.para || ''"
            @change="muda('para', $event.target.value || undefined)"
          >
            <option v-for="o in PARA_SINO" :key="o.valor" :value="o.valor">
              {{ t(`${K}.PAINEL.${o.rotulo}`) }}
            </option>
          </select>
        </label>
        <div v-if="!config.para" :class="ROTULO">
          <ListaMarcar
            :opcoes="opcoesPessoas"
            :model-value="config.user_ids || []"
            @update:model-value="v => muda('user_ids', v)"
          />
          <span>{{ t(`${K}.PAINEL.QUEM_RECEBE_AJUDA`) }}</span>
        </div>
      </template>

      <template v-else-if="tipo === 'avisar_push'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.TITULO_PUSH`) }}
          <input
            :class="CAMPO"
            :value="config.titulo || ''"
            @input="muda('titulo', $event.target.value)"
          />
        </label>
        <CampoTexto
          :rotulo="t(`${K}.PAINEL.TEXTO`)"
          :linhas="2"
          :model-value="config.texto || ''"
          @update:model-value="v => muda('texto', v)"
        />
        <label class="flex items-center gap-2 text-[13px] text-n-slate-12">
          <input
            data-testid="push-uma-vez"
            type="checkbox"
            class="reset-base"
            :checked="!!config.uma_vez_por_dia"
            @change="marca('uma_vez_por_dia', $event.target.checked)"
          />
          {{ t(`${K}.PAINEL.UMA_VEZ_POR_DIA`) }}
        </label>
      </template>

      <template v-else-if="tipo === 'webhook'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.WEBHOOK_URL`) }}
          <input
            data-testid="webhook-url"
            :class="CAMPO"
            type="url"
            :value="config.url || ''"
            @input="muda('url', $event.target.value)"
          />
        </label>
        <p class="text-xs text-n-slate-10">
          {{ t(`${K}.PAINEL.WEBHOOK_AJUDA`) }}
        </p>
      </template>

      <template v-else-if="tipo === 'trocar_responsavel'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.PAPEL`) }}
          <select
            data-testid="papel"
            :class="SELECT"
            :value="config.papel || ''"
            @change="muda('papel', $event.target.value)"
          >
            <option value="" disabled>{{ t(`${K}.PAINEL.ESCOLHA`) }}</option>
            <option v-for="p in PAPEIS" :key="p" :value="p">
              {{ t(`${K}.PAPEIS.${p}`) }}
            </option>
          </select>
        </label>
        <label class="flex items-center gap-2 text-[13px] text-n-slate-12">
          <input
            data-testid="so-se-vazio"
            type="checkbox"
            class="reset-base"
            :checked="!!config.so_se_vazio"
            @change="marca('so_se_vazio', $event.target.checked)"
          />
          {{ t(`${K}.PAINEL.SO_SE_VAZIO`) }}
        </label>
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.PESSOA`) }}
          <select
            :class="SELECT"
            :value="config.user_id ?? ''"
            @change="muda('user_id', numeroOuNada($event.target.value))"
          >
            <option value="">{{ t(`${K}.PAINEL.DISTRIBUIR_NO_TIME`) }}</option>
            <option v-for="p in pessoas" :key="p.id" :value="p.id">
              {{ p.name }}
            </option>
          </select>
        </label>
      </template>

      <template v-else-if="tipo === 'preencher_campo'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.CHAVE_CAMPO`) }}
          <input
            data-testid="campo-chave"
            :class="CAMPO"
            :value="config.chave || ''"
            @input="muda('chave', $event.target.value)"
          />
          <span>{{ t(`${K}.PAINEL.CHAVE_CAMPO_AJUDA`) }}</span>
        </label>
        <CampoTexto
          :rotulo="t(`${K}.PAINEL.VALOR`)"
          :linhas="2"
          :model-value="config.valor || ''"
          @update:model-value="v => muda('valor', v)"
        />
      </template>

      <template v-else-if="tipo === 'esperar'">
        <div class="flex flex-col gap-1.5 text-[13px] text-n-slate-12">
          <label
            v-for="o in OPCOES_ESPERA"
            :key="o.modo"
            class="flex items-center gap-2"
          >
            <input
              type="radio"
              class="reset-base"
              :data-testid="`espera-${o.modo}`"
              :checked="modoEspera === o.modo"
              @change="trocaEspera(o.modo)"
            />
            {{ t(`${K}.PAINEL.${o.rotulo}`) }}
          </label>
        </div>
        <div v-if="pedeTempo" class="grid grid-cols-2 gap-2">
          <label :class="ROTULO">
            {{ t(`${K}.PAINEL.QUANTIDADE`) }}
            <input
              :class="CAMPO"
              type="number"
              min="1"
              :value="config.quantidade ?? 1"
              @change="muda('quantidade', Number($event.target.value))"
            />
          </label>
          <label :class="ROTULO">
            {{ t(`${K}.PAINEL.UNIDADE`) }}
            <select
              :class="SELECT"
              :value="config.unidade || 'dias'"
              @change="muda('unidade', $event.target.value)"
            >
              <option v-for="u in UNIDADES" :key="u" :value="u">
                {{ t(`${K}.UNIDADES.${u}`) }}
              </option>
            </select>
          </label>
        </div>
        <JanelaHorario
          v-if="modoEspera === 'horario'"
          :config="config"
          @update:config="c => emit('update:config', c)"
        />
        <p class="text-xs text-n-slate-10">
          {{ t(`${K}.PAINEL.${ajudaEspera}`) }}
        </p>
      </template>

      <template v-else-if="tipo === 'rotina'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.ROTINA`) }}
          <select
            data-testid="rotina"
            :class="SELECT"
            :value="config.rotina || ''"
            @change="muda('rotina', $event.target.value)"
          >
            <option value="" disabled>{{ t(`${K}.PAINEL.ESCOLHA`) }}</option>
            <option v-for="r in ROTINAS" :key="r" :value="r">
              {{ t(`${K}.ROTINAS.${r}`) }}
            </option>
          </select>
        </label>
        <p
          v-if="config.rotina"
          data-testid="rotina-ajuda"
          class="text-xs text-n-slate-10"
        >
          {{ t(`${K}.ROTINAS_AJUDA.${config.rotina}`) }}
        </p>
      </template>

      <p v-else-if="tipo === 'apagar_reuniao'" class="text-xs text-n-slate-10">
        {{ t(`${K}.PAINEL.APAGAR_REUNIAO_AJUDA`) }}
      </p>

      <p
        v-else-if="tipo === 'registrar_retomada'"
        class="text-xs text-n-slate-10"
      >
        {{ t(`${K}.PAINEL.REGISTRAR_RETOMADA_AJUDA`) }}
      </p>

      <p v-else-if="tipo === 'parar'" class="text-xs text-n-slate-10">
        {{ t(`${K}.PAINEL.PARAR_AJUDA`) }}
      </p>
    </div>

    <div v-if="!gatilho" class="flex gap-2 border-t border-n-weak px-4 py-3">
      <Button
        outline
        slate
        sm
        icon="i-lucide-copy"
        :label="t(`${K}.PAINEL.DUPLICAR`)"
        @click="emit('duplicar')"
      />
      <Button
        data-testid="painel-excluir"
        outline
        ruby
        sm
        icon="i-lucide-trash-2"
        :label="t(`${K}.PAINEL.EXCLUIR`)"
        @click="emit('excluir')"
      />
    </div>
  </div>
</template>
