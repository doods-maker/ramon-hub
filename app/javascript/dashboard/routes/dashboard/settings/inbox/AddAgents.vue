<script>
/* eslint no-console: 0 */
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';

import InboxMembersAPI from '../../../../api/inboxMembers';
// FORK-PONTO (ramon): assistente de IA escolhido já na criação da caixa (Eduardo 17/08)
import CaptainInboxesAPI from 'dashboard/api/captain/inboxes';
import { modoDefault } from 'dashboard/routes/dashboard/ramon/helpers/copilotoModo';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import router from '../../../index';
import PageHeader from '../SettingsSubPageHeader.vue';
import { useVuelidate } from '@vuelidate/core';

export default {
  components: {
    PageHeader,
    NextButton,
    TagInput,
  },
  validations: {
    selectedAgentIds: {
      isEmpty() {
        return !!this.selectedAgentIds.length;
      },
    },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      selectedAgentIds: [],
      isCreating: false,
      // '' = nenhum assistente nesta caixa (padrão: a IA só entra se o Eduardo escolher)
      selectedAssistantId: '',
    };
  },
  computed: {
    ...mapGetters({
      agentList: 'agents/getAgents',
      assistants: 'captainAssistants/getRecords',
    }),
    // rótulo do modo padrão vigente (env RAMON_COPILOTO_MODO_DEFAULT) pra avisar o que a IA vai fazer
    modoDefaultLabel() {
      return this.$t(`RAMON.COPILOTO.MODOS.${modoDefault()}.NOME`);
    },
    selectedAgentNames() {
      return this.selectedAgentIds.map(
        id => this.agentList.find(a => a.id === id)?.name ?? ''
      );
    },
    agentMenuItems() {
      return this.agentList
        .filter(({ id }) => !this.selectedAgentIds.includes(id))
        .map(({ id, name, thumbnail, avatar_url }) => ({
          label: name,
          value: id,
          action: 'select',
          thumbnail: { name, src: thumbnail || avatar_url || '' },
        }));
    },
  },
  mounted() {
    this.$store.dispatch('agents/get');
    this.$store.dispatch('captainAssistants/get');
  },
  methods: {
    handleAgentAdd({ value }) {
      if (!this.selectedAgentIds.includes(value)) {
        this.selectedAgentIds.push(value);
      }
    },
    handleAgentRemove(index) {
      this.selectedAgentIds.splice(index, 1);
    },
    async addAgents() {
      this.isCreating = true;
      const inboxId = this.$route.params.inbox_id;

      try {
        await InboxMembersAPI.update({
          inboxId,
          agentList: this.selectedAgentIds,
        });
        if (this.selectedAssistantId) {
          await CaptainInboxesAPI.create({
            assistantId: this.selectedAssistantId,
            inboxId,
          });
        }
        router.replace({
          name: 'settings_inbox_finish',
          params: {
            page: 'new',
            inbox_id: this.$route.params.inbox_id,
          },
        });
      } catch (error) {
        useAlert(error.message);
      }
      this.isCreating = false;
    },
  },
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <form class="flex flex-wrap flex-col mx-0" @submit.prevent="addAgents()">
      <div class="w-full">
        <PageHeader
          :header-title="$t('INBOX_MGMT.ADD.AGENTS.TITLE')"
          :header-content="$t('INBOX_MGMT.ADD.AGENTS.DESC')"
        />
      </div>
      <div>
        <div class="w-full mb-4">
          <label :class="{ error: v$.selectedAgentIds.$error }">
            {{ $t('INBOX_MGMT.ADD.AGENTS.TITLE') }}
            <div
              class="rounded-xl outline outline-1 -outline-offset-1 outline-n-weak hover:outline-n-strong px-2 py-2"
            >
              <TagInput
                :model-value="selectedAgentNames"
                :placeholder="$t('INBOX_MGMT.ADD.AGENTS.PICK_AGENTS')"
                :menu-items="agentMenuItems"
                show-dropdown
                skip-label-dedup
                @add="handleAgentAdd"
                @remove="handleAgentRemove"
              />
            </div>
            <span v-if="v$.selectedAgentIds.$error" class="message">
              {{ $t('INBOX_MGMT.ADD.AGENTS.VALIDATION_ERROR') }}
            </span>
          </label>
        </div>
        <div class="w-full mb-4">
          <label>
            {{ $t('INBOX_MGMT.ADD.AGENTS.ASSISTANT_TITLE') }}
            <select
              v-model="selectedAssistantId"
              data-testid="inbox-assistant-select"
              class="mt-1"
            >
              <option value="">
                {{ $t('INBOX_MGMT.ADD.AGENTS.ASSISTANT_NONE') }}
              </option>
              <option v-for="a in assistants" :key="a.id" :value="a.id">
                {{ a.name }}
              </option>
            </select>
            <span class="text-xs text-n-slate-11">
              {{
                selectedAssistantId
                  ? $t('INBOX_MGMT.ADD.AGENTS.ASSISTANT_HINT_ON', {
                      modo: modoDefaultLabel,
                    })
                  : $t('INBOX_MGMT.ADD.AGENTS.ASSISTANT_HINT_OFF')
              }}
            </span>
          </label>
        </div>
        <div class="w-full">
          <NextButton
            type="submit"
            :is-loading="isCreating"
            solid
            blue
            :label="$t('INBOX_MGMT.AGENTS.BUTTON_TEXT')"
          />
        </div>
      </div>
    </form>
  </div>
</template>
