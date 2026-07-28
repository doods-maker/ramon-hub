import { flushPromises, mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import ReuniaoDetalhe from '../../components/reunioes/ReuniaoDetalhe.vue';
import ReunioesAPI from 'dashboard/api/reunioes';

vi.mock('dashboard/api/reunioes', () => ({
  default: { show: vi.fn(), reprocessar: vi.fn(), delete: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('shared/composables/useMessageFormatter', () => ({
  useMessageFormatter: () => ({ formatMessage: texto => `<p>${texto}</p>` }),
}));

const detalhe = extra => ({
  id: 1,
  titulo: 'Semanal',
  status: 'pronta',
  ata: '## Resumo',
  transcricao: 'fala',
  audio_url: null,
  erro: null,
  user_name: 'Ramon',
  ...extra,
});

describe('ReuniaoDetalhe', () => {
  beforeEach(() => vi.clearAllMocks());

  it('renders the ata when pronta', async () => {
    ReunioesAPI.show.mockResolvedValue({ data: detalhe() });
    const wrapper = mount(ReuniaoDetalhe, { props: { reuniaoId: 1 } });
    await flushPromises();
    expect(wrapper.find('[data-testid="reuniao-ata"]').html()).toContain(
      'Resumo'
    );
    expect(wrapper.find('[data-testid="reuniao-reprocess"]').exists()).toBe(
      false
    );
  });

  it('shows processing hint while transcrevendo', async () => {
    ReunioesAPI.show.mockResolvedValue({
      data: detalhe({ status: 'transcrevendo', ata: null }),
    });
    const wrapper = mount(ReuniaoDetalhe, { props: { reuniaoId: 1 } });
    await flushPromises();
    expect(wrapper.find('[data-testid="reuniao-processing"]').exists()).toBe(
      true
    );
  });

  it('offers reprocessar on erro', async () => {
    ReunioesAPI.show.mockResolvedValue({
      data: detalhe({ status: 'erro', erro: 'boom', ata: null }),
    });
    ReunioesAPI.reprocessar.mockResolvedValue({
      data: detalhe({ status: 'transcrevendo', ata: null }),
    });
    const wrapper = mount(ReuniaoDetalhe, { props: { reuniaoId: 1 } });
    await flushPromises();
    await wrapper.find('[data-testid="reuniao-reprocess"]').trigger('click');
    expect(ReunioesAPI.reprocessar).toHaveBeenCalledWith(1);
  });
});
