<script setup>
// Painel direito do editor (mockup .painel): config do passo selecionado.
// Sempre emite config NOVA (o editor troca no node do Vue Flow).
import { computed } from 'vue';
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
import { PAPEIS, PASSOS, TIPOS_TAREFA, UNIDADES, gatilhoInfo } from './fluxo';
import CampoTexto from './CampoTexto.vue';
import ConfigAcoesChatwoot from './ConfigAcoesChatwoot.vue';
import ConfigCasos from './ConfigCasos.vue';
import ConfigAdvbox from './ConfigAdvbox.vue';
import ConfigCondicoes from './ConfigCondicoes.vue';
import ConfigGatilho from './ConfigGatilho.vue';
import ConfigIa from './ConfigIa.vue';
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
const esperaHorario = computed(() => config.value.ate === 'horario_comercial');

const muda = (chave, valor) =>
  emit('update:config', { ...config.value, [chave]: valor });
const numeroOuNada = v => (v === '' ? null : Number(v));
const modoEspera = horario =>
  emit(
    'update:config',
    horario
      ? { rotulo: config.value.rotulo, ate: 'horario_comercial' }
      : { rotulo: config.value.rotulo, quantidade: 1, unidade: 'dias' }
  );
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
        v-else-if="
          ['rascunho_texto', 'nota_privada', 'registrar_atividade'].includes(
            tipo
          )
        "
        :rotulo="t(`${K}.PAINEL.TEXTO`)"
        :model-value="config.texto || ''"
        @update:model-value="v => muda('texto', v)"
      />

      <label v-else-if="tipo === 'mover_etapa'" :class="ROTULO">
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

      <template v-else-if="tipo === 'criar_tarefa'">
        <CampoTexto
          :rotulo="t(`${K}.PAINEL.TITULO_TAREFA`)"
          :linhas="2"
          :model-value="config.titulo || ''"
          @update:model-value="v => muda('titulo', v)"
        />
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
          <label :class="ROTULO">
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
        <label :class="ROTULO">
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
        <div :class="ROTULO">
          {{ t(`${K}.PAINEL.QUEM_RECEBE`) }}
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
            <option v-for="p in PAPEIS" :key="p" :value="p">
              {{ t(`${K}.PAPEIS.${p}`) }}
            </option>
          </select>
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
          <label class="flex items-center gap-2">
            <input
              type="radio"
              class="reset-base"
              :checked="!esperaHorario"
              @change="modoEspera(false)"
            />
            {{ t(`${K}.PAINEL.ESPERAR_TEMPO`) }}
          </label>
          <label class="flex items-center gap-2">
            <input
              type="radio"
              class="reset-base"
              :checked="esperaHorario"
              @change="modoEspera(true)"
            />
            {{ t(`${K}.PAINEL.ESPERAR_HORARIO`) }}
          </label>
        </div>
        <div v-if="!esperaHorario" class="grid grid-cols-2 gap-2">
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
        <p class="text-xs text-n-slate-10">
          {{ t(`${K}.PAINEL.ESPERAR_AJUDA`) }}
        </p>
      </template>

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
