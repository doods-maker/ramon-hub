<script setup>
// Topo da ficha do contato (FORK ramon): os leads abertos da pessoa, com
// "Etapa · Tese · Responsável" e os atalhos para a conversa e o dossiê.
// Dados do /linha_da_vida; sem lead aberto (ou se falhar), o bloco não aparece.
import { ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import LinhaDaVidaAPI from 'dashboard/api/linhaDaVida';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import { CARTAO, TITULO } from '../../helpers/ui';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';
import { partesDaLinha } from '../../helpers/leadNaConversa';

const props = defineProps({
  contactId: { type: [Number, String], default: null },
});

const route = useRoute();
const leads = ref([]);

const carregar = async () => {
  leads.value = [];
  if (!props.contactId) return;
  try {
    const { data } = await LinhaDaVidaAPI.show(props.contactId);
    leads.value = (data.leads || []).filter(l => !l.is_won && !l.is_lost);
  } catch {
    leads.value = [];
  }
};

watch(() => props.contactId, carregar, { immediate: true });

const conversaUrl = lead =>
  frontendURL(
    `accounts/${route.params.accountId}/conversations/${lead.conversation_id}`
  );
</script>

<template>
  <section
    v-if="leads.length"
    data-testid="contato-lead-aberto"
    class="flex flex-col w-full gap-2"
    :class="CARTAO"
  >
    <h2 class="m-0" :class="TITULO">
      {{ $t('RAMON.CONTATO.LEAD_ABERTO') }}
    </h2>
    <div
      v-for="lead in leads"
      :key="lead.id"
      class="flex flex-wrap items-center justify-between gap-2"
    >
      <span class="flex items-center min-w-0 gap-2 text-sm text-n-slate-12">
        <span
          class="rounded-full size-2 shrink-0 bg-[var(--stage)]"
          :style="{ '--stage': lead.stage_color || DEFAULT_STAGE_COLOR }"
        />
        <span class="truncate">{{ partesDaLinha(lead).join(' · ') }}</span>
      </span>
      <div class="flex items-center gap-2">
        <router-link
          v-if="lead.conversation_id"
          v-slot="{ navigate }"
          custom
          :to="conversaUrl(lead)"
        >
          <Button
            sm
            icon="i-lucide-message-square"
            :label="$t('RAMON.FUNIL.OPEN_CONVERSATION')"
            @click="navigate"
          />
        </router-link>
        <router-link
          v-slot="{ navigate }"
          custom
          :to="{ name: 'ramon_lead_dossie', params: { leadId: lead.id } }"
        >
          <Button
            sm
            slate
            faded
            icon="i-lucide-file-text"
            :label="$t('RAMON.DOSSIE.OPEN')"
            @click="navigate"
          />
        </router-link>
      </div>
    </div>
  </section>
</template>
