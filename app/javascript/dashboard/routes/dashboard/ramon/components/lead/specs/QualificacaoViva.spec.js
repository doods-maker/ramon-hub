import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import QualificacaoViva from '../QualificacaoViva.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: k => k }),
}));

const alertSpy = vi.fn();
const clipboardSpy = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...a) => alertSpy(...a),
}));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: (...a) => clipboardSpy(...a),
}));

const thesis = {
  id: 1,
  name: 'Auxílio-acidente',
  items: [
    {
      id: 2,
      section: 'qualificacao',
      title: 'Trabalhava com carteira assinada?',
      content: 'g',
    },
    {
      id: 3,
      section: 'qualificacao',
      title: 'Sofreu o acidente no trajeto?',
      content: 'g2',
    },
    { id: 4, section: 'documento', title: 'CAT', content: 'A CAT.' },
  ],
};

const build = (updateSpy = vi.fn()) =>
  createStore({
    modules: {
      theses: {
        namespaced: true,
        getters: { getTheses: () => [thesis] },
        actions: { show: vi.fn() },
      },
      leads: { namespaced: true, actions: { update: updateSpy } },
    },
  });

const mountQualificacao = (lead, updateSpy = vi.fn(), extraProps = {}) =>
  shallowMount(QualificacaoViva, {
    props: { lead, ...extraProps },
    global: { plugins: [build(updateSpy)], mocks: { $t: k => k } },
  });

const baseLead = {
  id: 3,
  name: 'Ana',
  thesis_id: 1,
  custom_attributes: { foo: 'bar', qualificacao_status: { 2: 'ok' } },
};

describe('QualificacaoViva.vue', () => {
  beforeEach(() => {
    alertSpy.mockClear();
    clipboardSpy.mockClear();
  });

  const criterios = w =>
    w.findAll('[data-testid="qualificacao-criterio"]').map(c => c.text());

  it('mostra N/M e só as pendentes; respondidas ficam atrás do toggle', async () => {
    const wrapper = mountQualificacao(baseLead);
    expect(wrapper.find('[data-testid="qualificacao-count"]').text()).toContain(
      'RAMON.QUALIFICACAO.COUNT'
    );
    // 2 itens qualificacao (2 ok, 3 pendente); item 4 é documento, fica de fora
    expect(criterios(wrapper)).toEqual([
      expect.stringContaining('Sofreu o acidente no trajeto?'),
    ]);
    const toggle = wrapper.find('[data-testid="qualificacao-respondidas"]');
    expect(toggle.attributes('label')).toBe('RAMON.QUALIFICACAO.RESPONDIDAS');
    await toggle.trigger('click');
    expect(criterios(wrapper)).toHaveLength(2);
  });

  it('todas respondidas: uma linha teal "Qualificado" que abre a lista', async () => {
    const wrapper = mountQualificacao({
      ...baseLead,
      custom_attributes: { qualificacao_status: { 2: 'ok', 3: 'ok' } },
    });
    expect(wrapper.find('[data-testid="qualificacao-count"]').exists()).toBe(
      false
    );
    expect(criterios(wrapper)).toHaveLength(0);
    const linha = wrapper.find('[data-testid="qualificacao-ok"]');
    expect(linha.text()).toContain('RAMON.QUALIFICACAO.QUALIFICADO');
    await linha.trigger('click');
    expect(criterios(wrapper)).toHaveLength(2);
  });

  it('clicking a criterio cycles ok->falta->null and PATCHes only qualificacao_status', async () => {
    const update = vi.fn();
    const wrapper = mountQualificacao(baseLead, update);
    await wrapper
      .find('[data-testid="qualificacao-respondidas"]')
      .trigger('click');
    // item 2 já está 'ok' -> vira 'falta'
    await wrapper
      .findAll('[data-testid="qualificacao-toggle"]')[0]
      .trigger('click');
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 3,
      custom_attributes: { qualificacao_status: { 2: 'falta' } },
    });
  });

  it('clicking a criterio with an unexpected status self-heals to ok', async () => {
    const update = vi.fn();
    const leadComLixo = {
      ...baseLead,
      custom_attributes: { qualificacao_status: { 2: 'xyz' } },
    };
    // status desconhecido conta como pendente: fica à vista
    const wrapper = mountQualificacao(leadComLixo, update);
    await wrapper
      .findAll('[data-testid="qualificacao-toggle"]')[0]
      .trigger('click');
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 3,
      custom_attributes: { qualificacao_status: { 2: 'ok' } },
    });
  });

  it('"perguntar ->" in conversation context emits insertIntoNormalEditor with the item title', async () => {
    const wrapper = mountQualificacao(baseLead, vi.fn(), {
      context: 'conversation',
    });
    const spy = vi.spyOn(emitter, 'emit');
    // item 3 (sem status) tem botão perguntar
    await wrapper
      .findAll('[data-testid="qualificacao-perguntar"]')[0]
      .trigger('click');
    expect(spy).toHaveBeenCalledWith(
      BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR,
      'Sofreu o acidente no trajeto?'
    );
  });

  it('"perguntar ->" in drawer context copies to clipboard instead of emitting', async () => {
    const wrapper = mountQualificacao(baseLead, vi.fn(), { context: 'drawer' });
    const spy = vi.spyOn(emitter, 'emit');
    await wrapper
      .findAll('[data-testid="qualificacao-perguntar"]')[0]
      .trigger('click');
    expect(clipboardSpy).toHaveBeenCalledWith('Sofreu o acidente no trajeto?');
    expect(spy).not.toHaveBeenCalled();
    expect(alertSpy).toHaveBeenCalledWith('RAMON.DOCS.COPIED');
  });

  it('does not render when the lead has no thesis or the thesis has no qualificacao items', () => {
    const semTese = mountQualificacao({ id: 3, thesis_id: null });
    expect(
      semTese.find('[data-testid="panel-card-qualificacao"]').exists()
    ).toBe(false);

    const teseSemQuiz = createStore({
      modules: {
        theses: {
          namespaced: true,
          getters: {
            getTheses: () => [
              {
                id: 9,
                name: 'Outra',
                items: [{ id: 1, section: 'documento' }],
              },
            ],
          },
          actions: { show: vi.fn() },
        },
        leads: { namespaced: true, actions: { update: vi.fn() } },
      },
    });
    const semCriterios = shallowMount(QualificacaoViva, {
      props: { lead: { id: 4, thesis_id: 9 } },
      global: { plugins: [teseSemQuiz], mocks: { $t: k => k } },
    });
    expect(
      semCriterios.find('[data-testid="panel-card-qualificacao"]').exists()
    ).toBe(false);
  });
});
