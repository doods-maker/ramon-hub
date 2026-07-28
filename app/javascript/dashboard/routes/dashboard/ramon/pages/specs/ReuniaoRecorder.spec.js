import { mount } from '@vue/test-utils';
import ReuniaoRecorder from '../../components/reunioes/ReuniaoRecorder.vue';
import ReunioesAPI from 'dashboard/api/reunioes';

vi.mock('dashboard/api/reunioes', () => ({
  default: { criar: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

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
});
