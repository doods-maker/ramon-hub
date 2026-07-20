<script setup>
import { computed } from 'vue';
import { onKeyStroke } from '@vueuse/core';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import LeadFields from 'dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue';
import LeadHistory from 'dashboard/routes/dashboard/ramon/components/conversation/LeadHistory.vue';
import LeadPlaybook from 'dashboard/routes/dashboard/ramon/components/conversation/LeadPlaybook.vue';
import LeadTriage from 'dashboard/routes/dashboard/ramon/components/conversation/LeadTriage.vue';
import LeadKit from 'dashboard/routes/dashboard/ramon/components/conversation/LeadKit.vue';
import LeadSimulador from 'dashboard/routes/dashboard/ramon/components/conversation/LeadSimulador.vue';
import { useLeadPanelSections } from 'dashboard/routes/dashboard/ramon/composables/useLeadPanelSections';

const emit = defineEmits(['openConversation']);
const store = useStore();
const getters = useStoreGetters();

const lead = computed(() => getters['leads/getSelectedLead'].value);

const close = () => store.dispatch('leads/select', null);

// Esc em pilha: com o dock aberto por cima, o Esc é dele — a gaveta ignora.
onKeyStroke('Escape', () => {
  if (!getters['leads/getDockConversationId'].value) close();
});

// MESMO storage do LeadConversationPanel: gaveta e painel da conversa mantêm
// as seções abertas/recolhidas sincronizadas.
const { openSections, toggleSection } = useLeadPanelSections();
</script>

<template>
  <Transition
    enter-active-class="transition duration-150"
    leave-active-class="transition duration-150"
    enter-from-class="opacity-0 translate-x-4"
    leave-to-class="opacity-0 translate-x-4"
  >
    <div v-if="lead" class="fixed inset-0 z-40 flex justify-end">
      <div
        class="absolute inset-0 bg-black/50"
        data-testid="drawer-overlay"
        @click="close"
      />
      <aside
        class="relative z-10 flex flex-col w-96 max-w-full h-full bg-n-solid-1 border-l border-n-weak"
      >
        <div class="flex items-center justify-between px-5 pt-5 pb-3">
          <h2 class="text-lg font-cormorant text-n-slate-12 truncate">
            {{ lead.name }}
          </h2>
          <button
            data-testid="drawer-close"
            class="text-n-slate-10 hover:text-n-slate-12"
            @click="close"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </div>

        <div class="flex flex-wrap gap-2 px-5 pb-3">
          <button
            v-if="lead.conversation_id"
            data-testid="drawer-open-conversation"
            class="flex items-center gap-1 px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
            @click="emit('openConversation', lead.conversation_id)"
          >
            <span class="i-lucide-message-square size-4" />{{
              $t('RAMON.FUNIL.OPEN_CONVERSATION')
            }}
          </button>
          <router-link
            v-if="lead.contact_id"
            data-testid="drawer-linha-da-vida"
            :to="{
              name: 'ramon_linha_da_vida',
              params: { contactId: lead.contact_id },
            }"
            class="flex items-center gap-1 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak hover:bg-n-alpha-2"
            @click="close"
          >
            <span class="i-lucide-git-commit-vertical size-4" />{{
              $t('RAMON.LINHA_DA_VIDA.OPEN')
            }}
          </router-link>
          <router-link
            data-testid="drawer-dossie"
            :to="{ name: 'ramon_lead_dossie', params: { leadId: lead.id } }"
            class="flex items-center gap-1 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak hover:bg-n-alpha-2"
            @click="close"
          >
            <span class="i-lucide-file-text size-4" />{{
              $t('RAMON.DOSSIE.OPEN')
            }}
          </router-link>
        </div>

        <!-- mesmo clamp do painel da conversa (#65): nunca rola na horizontal -->
        <div
          class="flex flex-col gap-2 flex-1 min-w-0 overflow-y-auto overflow-x-hidden px-5 pb-5"
        >
          <AccordionItem
            :title="$t('RAMON.LEAD_PANEL.TABS.SUMMARY')"
            :is-open="openSections.resumo"
            data-testid="drawer-section-resumo"
            @toggle="toggleSection('resumo')"
          >
            <LeadFields :lead="lead" />
          </AccordionItem>
          <AccordionItem
            :title="$t('RAMON.LEAD_PANEL.TABS.HISTORY')"
            :is-open="openSections.historico"
            data-testid="drawer-section-historico"
            @toggle="toggleSection('historico')"
          >
            <LeadHistory :lead-id="lead.id" />
          </AccordionItem>
          <AccordionItem
            :title="$t('RAMON.LEAD_PANEL.TABS.PLAYBOOK')"
            :is-open="openSections.playbook"
            data-testid="drawer-section-playbook"
            @toggle="toggleSection('playbook')"
          >
            <LeadPlaybook :lead="lead" />
          </AccordionItem>
          <AccordionItem
            :title="$t('RAMON.TRIAGE.TAB')"
            :is-open="openSections.triagem"
            data-testid="drawer-section-triagem"
            @toggle="toggleSection('triagem')"
          >
            <LeadTriage :lead="lead" />
          </AccordionItem>
          <AccordionItem
            :title="$t('RAMON.KIT.TAB')"
            :is-open="openSections.kit"
            data-testid="drawer-section-kit"
            @toggle="toggleSection('kit')"
          >
            <LeadKit :lead="lead" />
          </AccordionItem>
          <AccordionItem
            :title="$t('RAMON.SIMULADOR.TAB')"
            :is-open="openSections.simulador"
            data-testid="drawer-section-simulador"
            @toggle="toggleSection('simulador')"
          >
            <LeadSimulador :lead="lead" />
          </AccordionItem>
        </div>
      </aside>
    </div>
  </Transition>
</template>
