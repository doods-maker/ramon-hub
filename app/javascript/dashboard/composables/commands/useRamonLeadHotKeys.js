import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { brlCompact } from 'dashboard/routes/dashboard/ramon/helpers/currency';
import { prescriptionInfo } from 'dashboard/routes/dashboard/ramon/helpers/prescription';
import {
  ICON_ASSIGN_TEAM,
  ICON_SNOOZE_UNTIL_TOMORRROW,
  ICON_SEND_TRANSCRIPT,
  ICON_REPORTS_OVERVIEW,
} from 'dashboard/helper/commandbar/icons';

// Tile de iniciais bronze (mock 3b) no lugar do ícone genérico de contato.
// Só letras/números entram nas iniciais — nome vira HTML via unsafeHTML.
const initials = name =>
  (name || '')
    .trim()
    .split(/\s+/)
    .map(word => (word.match(/[\p{L}\p{N}]/u) || [''])[0])
    .filter(Boolean)
    .slice(0, 2)
    .join('')
    .toUpperCase();

const leadIcon = lead =>
  `<svg role="img" class="ninja-icon" width="24" height="24" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><rect width="24" height="24" rx="6" fill="#463528"/><text x="12" y="12.5" text-anchor="middle" dominant-baseline="central" font-family="Inter, sans-serif" font-size="9" font-weight="600" fill="#ece7df">${initials(lead.name)}</text></svg>`;

const MAX_LEADS = 15;
const PANEL_TAB_KEY = 'ramon_lead_panel_tab';

// Risco = prescrevendo (parcelas já perdidas ou a <6m do penhasco) OU tarefa
// vencida — esses leads sobem para o topo da seção.
const isAtRisk = lead => {
  const p = prescriptionInfo(lead);
  if (p && (p.lostInstallments > 0 || p.monthsToCliff <= 6)) return true;
  if (!lead.next_task_due_at) return false;
  const due = new Date(lead.next_task_due_at).getTime();
  return !Number.isNaN(due) && due < Date.now();
};

// "<nome> — <etapa> · <benefício> · R$ X" (partes vazias somem).
const leadTitle = lead => {
  const meta = [lead.stage_name, lead.benefit_type_name];
  if (lead.value !== null && lead.value !== undefined && lead.value !== '') {
    meta.push(brlCompact(lead.value));
  }
  const metaText = meta.filter(Boolean).join(' · ');
  return metaText ? `${lead.name} — ${metaText}` : lead.name;
};

export function useRamonLeadHotKeys() {
  const { t } = useI18n();
  const store = useStore();
  const router = useRouter();

  const leads = useMapGetter('leads/getLeads');
  const stages = useMapGetter('leadConfig/getStages');
  const accountId = useMapGetter('getCurrentAccountId');

  const openFunnelWithLead = leadId => {
    router.push({
      name: 'ramon_funil',
      params: { accountId: accountId.value },
    });
    store.dispatch('leads/select', leadId);
  };

  const moveLead = async (lead, stage) => {
    try {
      await store.dispatch('leads/move', {
        id: lead.id,
        leadStageId: stage.id,
      });
      useAlert(t('RAMON.KANBAN.MOVE_DONE'));
    } catch (e) {
      useAlert(t('RAMON.CMDK.MOVE_ERROR'));
    }
  };

  const createFollowUpTask = async lead => {
    const due = new Date();
    due.setDate(due.getDate() + 1);
    due.setHours(9, 0, 0, 0);
    try {
      await store.dispatch('leadTasks/create', {
        leadId: lead.id,
        title: t('RAMON.KANBAN.BELL.DEFAULT_TITLE'),
        kind: 'follow_up',
        dueAt: due.toISOString(),
      });
      useAlert(t('RAMON.KANBAN.CARD.TASK_SCHEDULED'));
    } catch (e) {
      useAlert(t('RAMON.TASKS.CREATE_ERROR'));
    }
  };

  const openDossie = lead => {
    router.push({
      name: 'ramon_lead_dossie',
      params: { accountId: accountId.value, leadId: lead.id },
    });
  };

  const openSimulator = lead => {
    try {
      localStorage.setItem(PANEL_TAB_KEY, 'simulador');
    } catch (e) {
      // localStorage indisponível: a gaveta abre na aba padrão
    }
    openFunnelWithLead(lead.id);
  };

  const buildLeadActions = (lead, targetStages, section) => {
    const base = `ramon_lead_${lead.id}`;
    const stageActions = targetStages.map(stage => ({
      id: `${base}_move_${stage.id}`,
      parent: `${base}_move`,
      section,
      title: stage.name,
      icon: ICON_ASSIGN_TEAM,
      handler: () => moveLead(lead, stage),
    }));
    // Atalhos M/T/D/S ficam só no rótulo: o `hotkey` do ninja-keys registra
    // binding GLOBAL (hotkeys-js), ativo mesmo com o palette fechado — uma
    // letra solta por lead seria um desastre.
    return [
      {
        id: base,
        section,
        title: leadTitle(lead),
        keywords: [lead.name, lead.contact_phone].filter(Boolean).join(' '),
        icon: leadIcon(lead),
        children: [
          `${base}_move`,
          `${base}_task`,
          `${base}_dossie`,
          `${base}_sim`,
        ],
        // ↵ já abre a gaveta no funil; keepOpen mantém o palette aberto
        // mostrando as ações do lead (Esc cai direto na gaveta).
        handler: () => {
          openFunnelWithLead(lead.id);
          return { keepOpen: true };
        },
      },
      {
        id: `${base}_move`,
        parent: base,
        section,
        title: t('RAMON.CMDK.MOVE'),
        icon: ICON_ASSIGN_TEAM,
        children: stageActions.map(action => action.id),
      },
      ...stageActions,
      {
        id: `${base}_task`,
        parent: base,
        section,
        title: t('RAMON.CMDK.TASK'),
        icon: ICON_SNOOZE_UNTIL_TOMORRROW,
        handler: () => createFollowUpTask(lead),
      },
      {
        id: `${base}_dossie`,
        parent: base,
        section,
        title: t('RAMON.CMDK.DOSSIE'),
        icon: ICON_SEND_TRANSCRIPT,
        handler: () => openDossie(lead),
      },
      {
        id: `${base}_sim`,
        parent: base,
        section,
        title: t('RAMON.CMDK.SIMULATE'),
        icon: ICON_REPORTS_OVERVIEW,
        handler: () => openSimulator(lead),
      },
    ];
  };

  const ramonLeadHotKeys = computed(() => {
    const records = leads.value || [];
    if (!records.length) return [];
    // ponytail: etapas de perda ficam fora do submenu — perder exige motivo
    // (LostReasonModal do funil), complexo demais para o palette.
    const targetStages = (stages.value || [])
      .filter(stage => !stage.is_lost)
      .sort((a, b) => a.position - b.position);
    const section = t('RAMON.CMDK.SECTION');
    return records
      .slice()
      .sort((a, b) => {
        const risk = Number(isAtRisk(b)) - Number(isAtRisk(a));
        if (risk) return risk;
        return (Number(b.value) || 0) - (Number(a.value) || 0);
      })
      .slice(0, MAX_LEADS)
      .flatMap(lead => buildLeadActions(lead, targetStages, section));
  });

  // Chamado na abertura do palette: hidrata funil/etapas se ainda não houver.
  // ponytail: re-tenta a cada abertura enquanto vazio — custo irrisório.
  const ensureLeadsLoaded = () => {
    if (
      !leads.value?.length &&
      !store.getters['leads/getUIFlags']?.isFetching
    ) {
      store.dispatch('leads/get');
    }
    if (!stages.value?.length) store.dispatch('leadConfig/get');
  };

  return { ramonLeadHotKeys, ensureLeadsLoaded };
}
