// Peças comuns das abas das Execuções (ferramentas da IA e agente Claude).
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';

// ok/erro (ferramentas) + limite, cap e timeout (agente_execucoes.status).
export const STATUS_TOM = {
  ok: TOM.teal,
  erro: TOM.ruby,
  timeout: TOM.amber,
  limite: TOM.amber,
  cap: TOM.slate,
};
export const LINK = 'text-xs text-n-blue-11 hover:underline';

export const fmtHora = value =>
  new Date(value).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

export const rotuloCaso = (t, item) =>
  item.lead_nome
    ? t('INTEL.EXECUCOES.CASO_NOME', { id: item.lead_id, nome: item.lead_nome })
    : t('INTEL.EXECUCOES.CASO', { id: item.lead_id });

// Mesmo padrão do Vigia: abre o Funil e seleciona o caso; a conversa pelo nº.
export const useAbrir = () => {
  const router = useRouter();
  const store = useStore();
  const { accountScopedRoute } = useAccount();
  return {
    abrirCaso: id => {
      router.push(accountScopedRoute('ramon_funil'));
      store.dispatch('leads/select', id);
    },
    abrirConversa: displayId =>
      router.push(
        accountScopedRoute('inbox_conversation', { conversation_id: displayId })
      ),
  };
};
