import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { papelDe } from '../helpers/papel';

export const useRamonPapel = () => {
  const { isAdmin } = useAdmin();
  const meusTimes = useMapGetter('teams/getMyTeams');
  const papel = computed(() =>
    papelDe({
      isAdmin: isAdmin.value,
      nomesDosTimes: (meusTimes.value || []).map(time => time.name),
    })
  );
  return { papel };
};
