<script setup>
import { useMapGetter } from 'dashboard/composables/store.js';
import { frontendURL } from '../../../helper/URLHelper';

import SearchResultSection from './SearchResultSection.vue';

defineProps({
  leads: {
    type: Array,
    default: () => [],
  },
  query: {
    type: String,
    default: '',
  },
  isFetching: {
    type: Boolean,
    default: false,
  },
  showTitle: {
    type: Boolean,
    default: true,
  },
});

const accountId = useMapGetter('getCurrentAccountId');

// Destino primário: Linha da Vida da pessoa (rota ramon_linha_da_vida).
const leadUrl = lead => {
  if (lead.contactId) {
    return frontendURL(
      `accounts/${accountId.value}/ramon/pessoa/${lead.contactId}`
    );
  }
  if (lead.conversationId) {
    return frontendURL(
      `accounts/${accountId.value}/conversations/${lead.conversationId}`
    );
  }
  return frontendURL(`accounts/${accountId.value}/ramon/funil`);
};
</script>

<template>
  <SearchResultSection
    :title="$t('SEARCH.SECTION.LEADS')"
    :empty="!leads.length"
    :query="query"
    :show-title="showTitle"
    :is-fetching="isFetching"
  >
    <ul v-if="leads.length" class="space-y-3 list-none">
      <li v-for="lead in leads" :key="lead.id">
        <router-link
          :to="leadUrl(lead)"
          class="flex items-center justify-between gap-2 p-2 rounded-md hover:bg-n-alpha-1"
        >
          <div class="min-w-0">
            <p class="text-sm truncate text-n-slate-12">{{ lead.name }}</p>
            <p class="text-xs truncate text-n-slate-10">
              <span v-if="lead.contactName">{{ lead.contactName }} · </span>
              <span v-if="lead.contactPhone">{{ lead.contactPhone }} · </span>
              <span v-if="lead.benefitTypeName">{{
                lead.benefitTypeName
              }}</span>
            </p>
          </div>
          <span
            v-if="lead.stageName"
            class="shrink-0 px-2 py-0.5 text-xs rounded-full text-n-slate-12"
            :style="{ backgroundColor: lead.stageColor || 'transparent' }"
          >
            {{ lead.stageName }}
          </span>
        </router-link>
      </li>
    </ul>
  </SearchResultSection>
</template>
