import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import LeadsAPI from 'dashboard/api/leads';
import { usePulaDocumentos } from '../usePulaDocumentos';
import MotivoPulaDocumentos from '../../components/MotivoPulaDocumentos.vue';

const getters = {};
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => ({
    get value() {
      return getters[key];
    },
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k, p) => (p ? `${k} ${JSON.stringify(p)}` : k) }),
}));
vi.mock('dashboard/api/leads', () => ({ default: { createNote: vi.fn() } }));

const novo = { id: 1, is_won: false };
const fechado = { id: 7, name: 'Fechado', label: 'fase-fechado', is_won: true };
const documentos = { id: 8, label: 'fase-documentos', is_won: true };
const lead = { thesis_passa_documentos: true, docs_total: 2 };

describe('usePulaDocumentos', () => {
  beforeEach(() => {
    getters['leadConfig/getStages'] = [novo, fechado, documentos];
    getters['leadConfig/getEtapaDocumentos'] = true;
  });

  it('pedeMotivo lê etapas e chave do store', () => {
    const { pedeMotivo } = usePulaDocumentos();
    expect(pedeMotivo(fechado, novo, lead)).toBe(true);
    getters['leadConfig/getEtapaDocumentos'] = false;
    expect(pedeMotivo(fechado, novo, lead)).toBe(false);
  });

  it('documentos é a etapa Documentos do funil', () => {
    expect(usePulaDocumentos().documentos.value).toEqual(documentos);
  });

  it('anotar grava a nota com etapa e motivo; falha avisa e devolve false', async () => {
    const { anotar } = usePulaDocumentos();
    LeadsAPI.createNote.mockResolvedValueOnce({});
    expect(await anotar(10, fechado, 'Pasta pronta')).toBe(true);
    expect(LeadsAPI.createNote).toHaveBeenCalledWith(
      10,
      'RAMON.FUNIL.WON.NOTA_PULA_DOCUMENTOS {"etapa":"Fechado","motivo":"Pasta pronta"}'
    );

    LeadsAPI.createNote.mockRejectedValueOnce(new Error('500'));
    expect(await anotar(10, fechado, 'x')).toBe(false);
    expect(useAlert).toHaveBeenCalledWith('RAMON.FUNIL.WON.NOTA_ERRO');
  });
});

describe('MotivoPulaDocumentos.vue', () => {
  it('padrão: ir para Documentos, sem campo de motivo; ficar mostra o campo e o v-model sobe o texto', async () => {
    const motivo = ref('');
    const ficar = ref(false);
    const wrapper = mount(MotivoPulaDocumentos, {
      props: {
        modelValue: motivo.value,
        'onUpdate:modelValue': v => {
          motivo.value = v;
        },
        ficar: ficar.value,
        'onUpdate:ficar': v => {
          ficar.value = v;
          wrapper.setProps({ ficar: v });
        },
      },
      global: { mocks: { $t: k => k } },
    });
    expect(
      wrapper.find('[data-testid="pula-documentos-ir"]').element.checked
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="motivo-pula-documentos"]').exists()
    ).toBe(false);
    await wrapper.find('[data-testid="pula-documentos-ficar"]').setValue(true);
    expect(ficar.value).toBe(true);
    const campo = wrapper.find(
      'label textarea[data-testid="motivo-pula-documentos"]'
    );
    await campo.setValue('Já trouxe tudo');
    expect(motivo.value).toBe('Já trouxe tudo');
  });
});
