import { mount, flushPromises } from '@vue/test-utils';
import ContactAPI from 'dashboard/api/contacts';
import LeadsAPI from 'dashboard/api/leads';
import CalculosAPI from 'dashboard/api/calculos';
import VincularCalculo from '../VincularCalculo.vue';

const alertSpy = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...a) => alertSpy(...a),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/api/contacts', () => ({ default: { search: vi.fn() } }));
vi.mock('dashboard/api/leads', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/calculos', () => ({ default: { vincular: vi.fn() } }));

const calculo = { id: 9, created_at: '2026-09-28T14:32:00.000Z' };

const montarAteOCaso = async () => {
  ContactAPI.search.mockResolvedValue({
    data: { payload: [{ id: 5, name: 'João Carlos Pereira' }] },
  });
  LeadsAPI.get.mockResolvedValue({
    data: { payload: [{ id: 40, thesis_name: 'Auxílio-acidente' }] },
  });
  const wrapper = mount(VincularCalculo, {
    props: { calculo },
    global: { mocks: { $t: k => k } },
  });
  await wrapper.find('[data-testid="vincular-busca"]').setValue('João');
  await new Promise(resolve => {
    setTimeout(resolve, 320); // debounce
  });
  await flushPromises();
  await wrapper.find('[data-testid="vincular-pessoa"]').trigger('click');
  await flushPromises();
  return wrapper;
};

describe('VincularCalculo.vue', () => {
  beforeEach(() => {
    CalculosAPI.vincular.mockReset();
    alertSpy.mockReset();
  });

  it('busca a pessoa, escolhe o caso e vincula', async () => {
    CalculosAPI.vincular.mockResolvedValue({ data: { lead_id: 40 } });
    const wrapper = await montarAteOCaso();

    expect(LeadsAPI.get).toHaveBeenCalledWith({ contact_id: 5 });
    await wrapper.find('[data-testid="vincular-caso"]').trigger('click');
    await flushPromises();

    expect(CalculosAPI.vincular).toHaveBeenCalledWith(9, 40, false);
    expect(wrapper.emitted('vinculado')[0][0]).toEqual({ lead_id: 40 });
  });

  it('caso com outro CNIS: pergunta e só substitui depois de confirmar', async () => {
    CalculosAPI.vincular
      .mockRejectedValueOnce({ response: { status: 409 } })
      .mockResolvedValueOnce({ data: { lead_id: 40 } });
    const wrapper = await montarAteOCaso();
    await wrapper.find('[data-testid="vincular-caso"]').trigger('click');
    await flushPromises();

    expect(wrapper.emitted('vinculado')).toBeUndefined();
    expect(wrapper.text()).toContain('RAMON.CALCULOS.VINCULAR_SUBSTITUIR');
    await wrapper.find('[data-testid="vincular-substituir"]').trigger('click');
    await flushPromises();

    expect(CalculosAPI.vincular).toHaveBeenLastCalledWith(9, 40, true);
    expect(wrapper.emitted('vinculado')).toHaveLength(1);
  });

  it('outro erro vira aviso', async () => {
    CalculosAPI.vincular.mockRejectedValue({ response: { status: 500 } });
    const wrapper = await montarAteOCaso();
    await wrapper.find('[data-testid="vincular-caso"]').trigger('click');
    await flushPromises();
    expect(alertSpy).toHaveBeenCalledWith('RAMON.CALCULOS.VINCULAR_ERRO');
  });
});
