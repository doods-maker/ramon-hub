import { mount, flushPromises } from '@vue/test-utils';
import ReuniaoRecorder from '../../components/reunioes/ReuniaoRecorder.vue';
import ReunioesAPI from 'dashboard/api/reunioes';
import { onBeforeRouteLeave } from 'vue-router';

vi.mock('dashboard/api/reunioes', () => ({
  default: { criar: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ onBeforeRouteLeave: vi.fn() }));

/* eslint-disable class-methods-use-this */
class FakeMediaRecorder {
  constructor() {
    FakeMediaRecorder.instance = this;
    this.ondataavailable = null;
    this.onstop = null;
  }

  start() {}

  pause() {}

  resume() {}

  stop() {
    this.ondataavailable?.({ data: new Blob(['x'], { type: 'audio/webm' }) });
    this.onstop?.();
  }
}
/* eslint-enable class-methods-use-this */
FakeMediaRecorder.isTypeSupported = () => true;

describe('ReuniaoRecorder', () => {
  beforeEach(() => {
    onBeforeRouteLeave.mockClear();
    vi.stubGlobal('MediaRecorder', FakeMediaRecorder);
    vi.stubGlobal('navigator', {
      mediaDevices: {
        getUserMedia: vi.fn().mockResolvedValue({ getTracks: () => [] }),
      },
    });
    ReunioesAPI.criar.mockResolvedValue({
      data: { id: 7, status: 'transcrevendo' },
    });
  });

  it('registers a leave guard that only blocks navigation while recording', async () => {
    const wrapper = mount(ReuniaoRecorder);
    const guard = onBeforeRouteLeave.mock.calls[0][0];

    expect(guard()).toBe(true); // estado 'parado' — nada pra perder

    await wrapper.find('[data-testid="recorder-start"]').trigger('click');
    const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(false);
    expect(guard()).toBe(false);
    expect(confirmSpy).toHaveBeenCalledWith('RAMON.REUNIOES.LEAVE_WARNING');
    confirmSpy.mockRestore();
  });

  it('records, uploads and emits created', async () => {
    const wrapper = mount(ReuniaoRecorder);
    await wrapper.find('[data-testid="recorder-start"]').trigger('click');
    await wrapper.vm.$nextTick();
    await wrapper.find('[data-testid="recorder-stop"]').trigger('click');
    await new Promise(resolve => {
      setTimeout(resolve);
    });
    expect(ReunioesAPI.criar).toHaveBeenCalled();
    const formData = ReunioesAPI.criar.mock.calls[0][0];
    expect(formData.get('audio')).toBeTruthy();
    expect(wrapper.emitted('created')[0][0]).toEqual({
      id: 7,
      status: 'transcrevendo',
    });
  });

  it('retries the upload after a failure and emits created on success', async () => {
    ReunioesAPI.criar
      .mockRejectedValueOnce(new Error('network'))
      .mockResolvedValueOnce({ data: { id: 9, status: 'transcrevendo' } });

    const wrapper = mount(ReuniaoRecorder);
    await wrapper.find('[data-testid="recorder-start"]').trigger('click');
    await wrapper.vm.$nextTick();
    await wrapper.find('[data-testid="recorder-stop"]').trigger('click');
    await flushPromises();

    expect(ReunioesAPI.criar).toHaveBeenCalledTimes(1);
    const retryButton = wrapper.find('[data-testid="recorder-retry"]');
    expect(retryButton.exists()).toBe(true);

    await retryButton.trigger('click');
    await flushPromises();

    expect(ReunioesAPI.criar).toHaveBeenCalledTimes(2);
    expect(wrapper.emitted('created')[0][0]).toEqual({
      id: 9,
      status: 'transcrevendo',
    });
  });
});
