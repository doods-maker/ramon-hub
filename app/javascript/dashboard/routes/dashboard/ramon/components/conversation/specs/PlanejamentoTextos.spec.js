import { mount } from '@vue/test-utils';
import { reactive } from 'vue';
import PlanejamentoTextos from '../PlanejamentoTextos.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const dados = () =>
  reactive({
    nome: 'Ana',
    cenarios: [
      { nome: 'Mínimo', rmi: 2234.62, lead: 'L', bom: ['a', 'b'] },
    ],
    pode: [{ t: 'T', p: 'P' }],
    sugestao: { curta: 'c', titulo: 't', itens: ['i'] },
    documentos: { separar: ['s'], guardar: ['g'] },
  });

const montar = d => mount(PlanejamentoTextos, { props: { dados: d } });

describe('PlanejamentoTextos', () => {
  it('um textarea por texto editável e nenhum para número', () => {
    const w = montar(dados());
    expect(w.findAll('textarea').length).toBe(10);
    expect(w.find('[data-testid="planejamento-texto-cenarios.0.rmi"]').exists()).toBe(
      false
    );
  });

  it('digitar muda o dados do pai', async () => {
    const d = dados();
    const w = montar(d);
    await w.find('[data-testid="planejamento-texto-pode.0.p"]').setValue('novo');
    expect(d.pode[0].p).toBe('novo');
  });

  it('observações internas avisam que não vão no PDF', () => {
    const w = montar(reactive({ observacoes_internas: [{ t: 'x', p: 'y' }] }));
    expect(w.text()).toContain('RAMON.SIMULADOR.PLANEJAMENTO_SO_ADVOGADO');
  });

  it('outras seções não levam o aviso', () => {
    const w = montar(dados());
    expect(w.text()).not.toContain('PLANEJAMENTO_SO_ADVOGADO');
  });
});
