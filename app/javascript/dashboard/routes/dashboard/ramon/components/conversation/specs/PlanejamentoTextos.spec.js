import { mount } from '@vue/test-utils';
import { reactive } from 'vue';
import PlanejamentoTextos from '../PlanejamentoTextos.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const dados = () =>
  reactive({
    nome: 'Ana',
    cenarios: [{ nome: 'Mínimo', rmi: 2234.62, lead: 'L', bom: ['a', 'b'] }],
    pode: [{ t: 'Pode isto', p: 'Explicação do pode' }],
    sugestao: { curta: 'c', titulo: 't', itens: ['i'] },
    documentos: { separar: ['s'], guardar: ['g'] },
  });

const montar = (d, props = {}) =>
  mount(PlanejamentoTextos, { props: { dados: d, ...props } });

const editar = (w, secao) =>
  w.find(`[data-testid="planejamento-editar-${secao}"]`).trigger('click');

describe('PlanejamentoTextos', () => {
  it('abre em leitura: mostra os textos sem nenhuma caixa', () => {
    const w = montar(dados());
    expect(w.findAll('textarea').length).toBe(0);
    expect(w.text()).toContain('Pode isto');
    expect(w.text()).toContain('Explicação do pode');
    expect(w.text()).not.toContain('2234');
  });

  it('Editar abre as caixas só daquela seção, e digitar muda o dados do pai', async () => {
    const d = dados();
    const w = montar(d);
    await editar(w, 'pode');
    expect(w.findAll('textarea').length).toBe(2);
    await w
      .find('[data-testid="planejamento-texto-pode.0.p"]')
      .setValue('novo');
    expect(d.pode[0].p).toBe('novo');
  });

  it('Pronto volta para a leitura já com o texto novo', async () => {
    const d = dados();
    const w = montar(d);
    await editar(w, 'pode');
    await w
      .find('[data-testid="planejamento-texto-pode.0.p"]')
      .setValue('texto corrigido');
    await editar(w, 'pode');
    expect(w.findAll('textarea').length).toBe(0);
    expect(w.text()).toContain('texto corrigido');
  });

  it('cada seção leva o seu título; seção ausente não aparece', () => {
    const w = montar(dados());
    expect(w.find('[data-testid="planejamento-secao-nao_pode"]').exists()).toBe(
      false
    );
    expect(w.find('[data-testid="planejamento-secao-pode"] h4').text()).toBe(
      'RAMON.SIMULADOR.PLANEJAMENTO_SECAO_PODE'
    );
  });

  it('secoes limita o que aparece', () => {
    const w = montar(dados(), { secoes: ['pode'] });
    expect(w.find('[data-testid="planejamento-secao-pode"]').exists()).toBe(
      true
    );
    expect(w.find('[data-testid="planejamento-secao-cenarios"]').exists()).toBe(
      false
    );
  });

  it('sem editavel não há botão Editar', () => {
    const w = montar(dados(), { editavel: false });
    expect(w.find('[data-testid="planejamento-editar-pode"]').exists()).toBe(
      false
    );
  });

  it('pendência mostra o rótulo de impacto do motor', () => {
    const w = montar(
      reactive({
        pendencias: [{ t: 'Vínculo aberto', imp: 'pode tirar tempo', p: 'x' }],
      })
    );
    expect(w.text()).toContain('pode tirar tempo');
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
