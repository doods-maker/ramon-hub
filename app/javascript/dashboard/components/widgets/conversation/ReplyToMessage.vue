<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import MessagePreview from 'dashboard/components/widgets/conversation/MessagePreview.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  autorCitacao,
  textoCitacao,
} from 'dashboard/routes/dashboard/ramon/helpers/equipe';

const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
  // FORK(ramon): caixa Equipe, com a citação do mockup (.resp)
  equipe: {
    type: Boolean,
    default: false,
  },
  meuId: {
    type: Number,
    default: null,
  },
});

const emit = defineEmits(['dismiss']);

const { t } = useI18n();
const autor = computed(() => autorCitacao(props.message, props.meuId, t));
const texto = computed(() => textoCitacao(props.message, t));
</script>

<template>
  <div
    :class="
      equipe
        ? 'flex items-center gap-2 mb-1.5'
        : 'reply-editor bg-n-slate-9/10 rounded-md py-1 pl-2 pr-1 text-xs tracking-wide mt-2 flex items-center gap-1.5'
    "
  >
    <div
      v-if="equipe"
      class="flex-1 min-w-0 px-2 py-1 text-xs rounded-md bg-n-slate-9/[.12] shadow-[inset_3px_0_0_rgb(var(--blue-11))]"
      data-testid="equipe-resposta"
    >
      <span v-if="autor" class="block font-semibold truncate text-n-blue-11">
        {{ autor }}
      </span>
      <span class="block truncate text-n-slate-11">{{ texto }}</span>
    </div>
    <template v-else>
      <fluent-icon class="flex-shrink-0 icon" icon="arrow-reply" size="14" />
      <div class="flex-grow gap-1 mt-px text-xs truncate">
        {{ $t('CONVERSATION.REPLYBOX.REPLYING_TO') }}
        <MessagePreview
          :message="message"
          :show-message-type="false"
          :default-empty-message="$t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND')"
          class="inline"
        />
      </div>
    </template>
    <Button
      v-tooltip="$t('CONVERSATION.REPLYBOX.DISMISS_REPLY')"
      ghost
      xs
      slate
      icon="i-lucide-x"
      class="flex-shrink-0"
      @click.stop="emit('dismiss')"
    />
  </div>
</template>

<style lang="scss">
// TODO: Remove this
// override for dashboard/assets/scss/widgets/_reply-box.scss
.reply-editor {
  .icon {
    margin-right: 0px !important;
  }
}
</style>
