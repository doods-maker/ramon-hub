<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatBrl } from '../../helpers/currency';
import { formatCpf } from '../../helpers/cpf';
import { prescriptionText } from '../../helpers/prescription';
import { CARTAO, CHIP, TITULO, TOM } from '../../helpers/ui';

// "Passagem ao jurídico" da ficha: o que o jurídico precisa pra assumir o caso,
// lido do que o hub já guarda (Ramon::DossiePassagem). Faltou dado = "—" ou o
// "ainda não" de cada item, nunca quebra.
const props = defineProps({
  passagem: { type: Object, required: true },
  entregando: { type: Boolean, default: false },
});
// "Dossiê entregue" (Painel do time): só no lead ganho; quem chama grava.
const emit = defineEmits(['entregar']);
defineOptions({ name: 'PassagemJuridico' });

const { t } = useI18n();
const p = computed(() => props.passagem);

// data pura (DCB, nascimento) ao meio-dia: sem escorregar de dia no fuso
const dia = (value, ano = true) => {
  if (!value) return '';
  const d = /^\d{4}-\d{2}-\d{2}$/.test(value)
    ? new Date(`${value}T12:00:00`)
    : new Date(value);
  return d.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    ...(ano ? { year: 'numeric' } : {}),
  });
};

const prescricao = computed(() =>
  prescriptionText(t, p.value.prescription, p.value.benefit_monthly_value)
);
const prescrevendo = computed(
  () => p.value.prescription?.lost_installments > 0
);

const contrato = computed(() => {
  const c = p.value.contrato;
  const k = 'RAMON.FICHA.PASSAGEM.';
  if (!c) return { cor: 'text-n-slate-11', label: t(`${k}CONTRACT_NONE`) };
  if (c.status === 'signed')
    return {
      cor: 'text-n-teal-11',
      label: c.assinado_em
        ? t(`${k}CONTRACT_SIGNED`, { date: dia(c.assinado_em, false) })
        : t(`${k}CONTRACT_SIGNED_NO_DATE`),
    };
  if (c.status === 'refused')
    return {
      cor: 'text-n-ruby-11',
      label: c.recusado_em
        ? t(`${k}CONTRACT_REFUSED`, { date: dia(c.recusado_em, false) })
        : t(`${k}CONTRACT_REFUSED_NO_DATE`),
    };
  if (c.status === 'cancelado')
    return { cor: 'text-n-slate-11', label: t(`${k}CONTRACT_CANCELLED`) };
  return {
    cor: 'text-n-amber-11',
    label: t(`${k}CONTRACT_SENT`, {
      date: c.criado_em ? dia(c.criado_em, false) : '—',
    }),
  };
});

const simulacao = computed(() => {
  const s = p.value.simulacao;
  if (!s) return [];
  return [
    ['SIM_ATRASADOS', s.atrasados],
    ['SIM_RMI', s.mensal],
    ['SIM_FEE', s.honorario_valor],
  ]
    .filter(([, valor]) => valor != null)
    .map(([chave, valor]) => ({
      rotulo: t(`RAMON.FICHA.PASSAGEM.${chave}`),
      valor: `~${formatBrl(valor)}`,
    }));
});

const reuniao = computed(() => p.value.reuniao);
</script>

<template>
  <section :class="CARTAO" class="!p-4" data-testid="ficha-passagem">
    <header class="flex flex-wrap items-center justify-between gap-2">
      <h2
        class="flex items-center gap-1.5 text-sm font-semibold text-n-slate-12"
      >
        <span class="i-lucide-briefcase size-4 text-n-slate-10" />
        {{ $t('RAMON.FICHA.PASSAGEM.TITLE') }}
      </h2>
      <span
        v-if="p.entrega?.entregue_em"
        data-testid="passagem-entregue"
        :class="[CHIP, TOM.teal]"
        :title="p.entrega.por"
      >
        <span class="i-lucide-check size-3" />
        {{
          $t('RAMON.FICHA.PASSAGEM.ENTREGUE_EM', {
            data: dia(p.entrega.entregue_em, false),
          })
        }}
      </span>
      <Button
        v-else-if="p.entrega"
        data-testid="passagem-entregar"
        sm
        faded
        teal
        icon="i-lucide-send"
        :disabled="entregando"
        :label="$t('RAMON.FICHA.PASSAGEM.ENTREGAR')"
        @click="emit('entregar')"
      />
    </header>

    <dl class="grid gap-x-6 gap-y-4 mt-3 sm:grid-cols-2 lg:grid-cols-4">
      <div>
        <dt :class="TITULO">{{ $t('RAMON.FICHA.PASSAGEM.CPF') }}</dt>
        <dd
          class="mt-1 text-sm font-mono text-n-slate-12"
          data-testid="passagem-cpf"
        >
          {{ p.cpf ? formatCpf(p.cpf) : '—' }}
        </dd>
      </div>
      <div>
        <dt :class="TITULO">{{ $t('RAMON.FICHA.PASSAGEM.BIRTH') }}</dt>
        <dd class="mt-1 text-sm font-mono text-n-slate-12">
          {{ p.nascimento ? dia(p.nascimento) : '—' }}
        </dd>
      </div>
      <div>
        <dt :class="TITULO">{{ $t('RAMON.FICHA.PASSAGEM.BENEFIT') }}</dt>
        <dd class="mt-1 text-sm text-n-slate-12">{{ p.beneficio || '—' }}</dd>
      </div>
      <div>
        <dt :class="TITULO">{{ $t('RAMON.FICHA.PASSAGEM.DCB') }}</dt>
        <dd class="mt-1 text-sm font-mono text-n-slate-12">
          {{ p.dcb_em ? dia(p.dcb_em) : '—' }}
        </dd>
      </div>

      <div>
        <dt :class="TITULO">{{ $t('RAMON.FICHA.PASSAGEM.PRESCRIPTION') }}</dt>
        <dd class="mt-1 text-sm" data-testid="passagem-prescricao">
          <span
            v-if="prescricao"
            class="flex items-start gap-1.5 font-medium"
            :class="prescrevendo ? 'text-n-ruby-11' : 'text-n-amber-11'"
          >
            <span class="i-lucide-hourglass size-3.5 mt-0.5 shrink-0" />
            {{ prescricao }}
          </span>
          <span v-else class="text-n-slate-10">—</span>
        </dd>
      </div>
      <div>
        <dt :class="TITULO">{{ $t('RAMON.FICHA.PASSAGEM.CONTRACT') }}</dt>
        <dd class="mt-1 text-sm" data-testid="passagem-contrato">
          <span
            class="flex items-start gap-1.5 font-medium"
            :class="contrato.cor"
          >
            <span class="mt-1.5 size-1.5 shrink-0 rounded-full bg-current" />
            {{ contrato.label }}
          </span>
        </dd>
      </div>
      <div>
        <dt :class="TITULO">{{ $t('RAMON.FICHA.PASSAGEM.ADVBOX') }}</dt>
        <dd class="mt-1 text-sm" data-testid="passagem-advbox">
          <span v-if="p.advbox?.lawsuits_id" class="font-medium text-n-teal-11">
            {{ $t('RAMON.ADVBOX.SYNCED', { lawsuit: p.advbox.lawsuits_id }) }}
          </span>
          <span v-else-if="p.advbox?.erro" class="text-n-ruby-11">
            {{ $t('RAMON.FICHA.PASSAGEM.ADVBOX_ERROR') }}
          </span>
          <span v-else class="text-n-slate-10">
            {{ $t('RAMON.FICHA.PASSAGEM.ADVBOX_NONE') }}
          </span>
        </dd>
      </div>
      <div>
        <dt :class="TITULO">{{ $t('RAMON.FICHA.PASSAGEM.DRIVE') }}</dt>
        <dd class="mt-1 text-sm" data-testid="passagem-drive">
          <a
            v-if="p.drive_url"
            :href="p.drive_url"
            target="_blank"
            rel="noopener noreferrer"
          >
            <Button
              link
              sm
              tabindex="-1"
              icon="i-lucide-folder-open"
              :label="$t('RAMON.FICHA.PASSAGEM.DRIVE_OPEN')"
            />
          </a>
          <span v-else class="text-n-slate-10">
            {{ $t('RAMON.FICHA.PASSAGEM.DRIVE_NONE') }}
          </span>
        </dd>
      </div>

      <div>
        <dt :class="TITULO">{{ $t('RAMON.FICHA.PASSAGEM.CNIS') }}</dt>
        <dd class="mt-1 text-sm text-n-slate-12" data-testid="passagem-cnis">
          <template v-if="p.cnis">
            {{
              $t('RAMON.FICHA.PASSAGEM.CNIS_SUMMARY', {
                competencias: p.cnis.competencias,
                vinculos: p.cnis.vinculos,
              })
            }}
            <span v-if="p.cnis.sexo" class="text-n-slate-11">
              · {{ $t('RAMON.FICHA.PASSAGEM.CNIS_SEX', { sexo: p.cnis.sexo }) }}
            </span>
          </template>
          <span v-else class="text-n-slate-10">
            {{ $t('RAMON.FICHA.PASSAGEM.CNIS_NONE') }}
          </span>
        </dd>
      </div>
      <div>
        <dt :class="TITULO">{{ $t('RAMON.FICHA.PASSAGEM.SIM') }}</dt>
        <dd class="mt-1 text-sm" data-testid="passagem-simulacao">
          <template v-if="p.simulacao">
            <p
              v-for="linha in simulacao"
              :key="linha.rotulo"
              class="text-n-slate-11"
            >
              {{ linha.rotulo }}
              <span class="font-mono font-medium text-n-slate-12">{{
                linha.valor
              }}</span>
            </p>
            <p v-if="p.simulacao.em" class="text-xs text-n-slate-10">
              {{
                $t('RAMON.FICHA.PASSAGEM.SIM_AT', {
                  date: dia(p.simulacao.em, false),
                })
              }}
            </p>
          </template>
          <span v-else class="text-n-slate-10">
            {{ $t('RAMON.FICHA.PASSAGEM.SIM_NONE') }}
          </span>
        </dd>
      </div>
      <div class="sm:col-span-2">
        <dt :class="TITULO">{{ $t('RAMON.FICHA.PASSAGEM.MEETING') }}</dt>
        <dd class="mt-1 text-sm" data-testid="passagem-reuniao">
          <template v-if="reuniao">
            <p class="flex flex-wrap items-center gap-1.5">
              <span
                v-if="reuniao.resultado"
                :class="[
                  CHIP,
                  reuniao.resultado === 'qualificada' ? TOM.teal : TOM.amber,
                ]"
              >
                {{ $t(`RAMON.REUNIAO.RESULTADO.${reuniao.resultado}`) }}
              </span>
              <span
                v-if="reuniao.registrada_em"
                class="font-mono text-xs text-n-slate-10"
              >
                {{ dia(reuniao.registrada_em) }}
              </span>
            </p>
            <p
              v-if="reuniao.ata_resumo"
              class="mt-1 text-[12.5px] italic text-n-slate-11 line-clamp-3"
            >
              {{ `“${reuniao.ata_resumo}”` }}
            </p>
            <router-link
              v-if="reuniao.reuniao_id"
              v-slot="{ navigate }"
              custom
              :to="{
                name: 'ramon_reuniao',
                params: { reuniaoId: reuniao.reuniao_id },
              }"
            >
              <Button
                data-testid="passagem-abrir-reuniao"
                link
                xs
                icon="i-lucide-file-text"
                :label="$t('RAMON.FICHA.PASSAGEM.OPEN_MEETING')"
                @click="navigate"
              />
            </router-link>
          </template>
          <span v-else class="text-n-slate-10">
            {{ $t('RAMON.FICHA.PASSAGEM.MEETING_NONE') }}
          </span>
        </dd>
      </div>
    </dl>
  </section>
</template>
