import { flushPromises, mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import ReuniaoDetalhe from '../../components/reunioes/ReuniaoDetalhe.vue';
import ReunioesAPI from 'dashboard/api/reunioes';

vi.mock('dashboard/api/reunioes', () => ({
  default: {
    show: vi.fn(),
    reprocessar: vi.fn(),
    delete: vi.fn(),
    vincularLead: vi.fn(),
  },
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

  it('deletes via ConfirmModal after confirming', async () => {
    ReunioesAPI.show.mockResolvedValue({ data: detalhe() });
    ReunioesAPI.delete.mockResolvedValue({});
    const wrapper = mount(ReuniaoDetalhe, { props: { reuniaoId: 1 } });
    await flushPromises();

    expect(wrapper.find('[data-testid="confirm-modal-confirm"]').exists()).toBe(
      false
    );
    await wrapper.find('[data-testid="reuniao-delete"]').trigger('click');
    expect(wrapper.find('[data-testid="confirm-modal-confirm"]').exists()).toBe(
      true
    );

    await wrapper
      .find('[data-testid="confirm-modal-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(ReunioesAPI.delete).toHaveBeenCalledWith(1);
    expect(wrapper.emitted('deleted')).toBeTruthy();
  });

  describe('lead da reunião', () => {
    const montar = () =>
      mount(ReuniaoDetalhe, {
        props: { reuniaoId: 1 },
        global: {
          mocks: { $t: k => k },
          stubs: {
            RouterLink: { template: '<a><slot /></a>' },
            ReuniaoVincularLead: true,
            teleport: true,
          },
        },
      });

    it('mostra o lead vinculado', async () => {
      ReunioesAPI.show.mockResolvedValue({
        data: detalhe({ lead_id: 8, lead_name: 'Maria Souza' }),
      });
      const wrapper = montar();
      await flushPromises();
      expect(
        wrapper.find('[data-testid="reuniao-lead-link"]').text()
      ).toContain('Maria Souza');
    });

    it('Vincular a um lead grava o caso escolhido', async () => {
      ReunioesAPI.show.mockResolvedValue({ data: detalhe() });
      ReunioesAPI.vincularLead.mockResolvedValue({
        data: detalhe({ lead_id: 9, lead_name: 'Rosângela' }),
      });
      const wrapper = montar();
      await flushPromises();
      expect(wrapper.find('[data-testid="reuniao-lead-link"]').exists()).toBe(
        false
      );
      await wrapper.find('[data-testid="reuniao-vincular"]').trigger('click');
      wrapper
        .findComponent({ name: 'ReuniaoVincularLead' })
        .vm.$emit('escolhido', { id: 9 });
      await flushPromises();
      expect(ReunioesAPI.vincularLead).toHaveBeenCalledWith(1, 9);
      expect(
        wrapper.find('[data-testid="reuniao-lead-link"]').text()
      ).toContain('Rosângela');
    });
  });
});
