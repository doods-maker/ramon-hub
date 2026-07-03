import axios from 'axios';
import { actions } from '../../theses';
import types from '../../../mutation-types';

global.axios = axios;
vi.mock('axios');

describe('theses actions', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('get faz commit de SET_THESES', async () => {
    const theses = [
      { id: 1, name: 'Auxílio-acidente', position: 0 },
      { id: 2, name: 'BPC/LOAS', position: 1 },
    ];
    axios.get.mockResolvedValue({ data: theses });
    const commit = vi.fn();
    await actions.get({ commit });
    expect(commit).toHaveBeenCalledWith(types.SET_THESES_UI_FLAG, {
      isFetching: true,
    });
    expect(commit).toHaveBeenCalledWith(types.SET_THESES, theses);
    expect(commit).toHaveBeenCalledWith(types.SET_THESES_UI_FLAG, {
      isFetching: false,
    });
  });

  it('show busca a tese com os itens e faz commit de EDIT_THESIS', async () => {
    const thesis = { id: 1, name: 'Auxílio-acidente', items: [] };
    axios.get.mockResolvedValue({ data: thesis });
    const commit = vi.fn();
    const result = await actions.show({ commit }, 1);
    expect(axios.get).toHaveBeenCalledWith(expect.stringContaining('/theses/1'));
    expect(commit).toHaveBeenCalledWith(types.EDIT_THESIS, thesis);
    expect(result).toEqual(thesis);
  });

  it('create posta a tese e faz commit de ADD_THESIS', async () => {
    const thesis = { id: 3, name: 'Trabalhista' };
    axios.post.mockResolvedValue({ data: thesis });
    const commit = vi.fn();
    const result = await actions.create({ commit }, { name: 'Trabalhista' });
    expect(commit).toHaveBeenCalledWith(types.ADD_THESIS, thesis);
    expect(result).toEqual(thesis);
  });

  it('update faz patch e commit de EDIT_THESIS', async () => {
    const thesis = { id: 1, name: 'Renomeada' };
    axios.patch.mockResolvedValue({ data: thesis });
    const commit = vi.fn();
    const result = await actions.update(
      { commit },
      { id: 1, name: 'Renomeada' }
    );
    expect(axios.patch).toHaveBeenCalledWith(
      expect.stringContaining('/theses/1'),
      { name: 'Renomeada' }
    );
    expect(commit).toHaveBeenCalledWith(types.EDIT_THESIS, thesis);
    expect(result).toEqual(thesis);
  });

  it('delete remove a tese e faz commit de DELETE_THESIS', async () => {
    axios.delete.mockResolvedValue({});
    const commit = vi.fn();
    await actions.delete({ commit }, 1);
    expect(commit).toHaveBeenCalledWith(types.DELETE_THESIS, 1);
  });

  it('reorder envia os ids e faz commit de SET_THESES', async () => {
    const theses = [
      { id: 2, position: 0 },
      { id: 1, position: 1 },
    ];
    axios.post.mockResolvedValue({ data: theses });
    const commit = vi.fn();
    await actions.reorder({ commit }, [2, 1]);
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('/theses/reorder'),
      { ids: [2, 1] }
    );
    expect(commit).toHaveBeenCalledWith(types.SET_THESES, theses);
  });

  it('createItem cria o item e atualiza a tese via show', async () => {
    axios.post.mockResolvedValue({ data: { id: 10 } });
    const dispatch = vi.fn();
    await actions.createItem(
      { dispatch },
      { thesisId: 1, section: 'abertura', title: 'Oi', content: 'Conteúdo' }
    );
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('/theses/1/thesis_items'),
      { section: 'abertura', title: 'Oi', content: 'Conteúdo' }
    );
    expect(dispatch).toHaveBeenCalledWith('show', 1);
  });

  it('updateItem atualiza o item e recarrega a tese via show', async () => {
    axios.patch.mockResolvedValue({ data: { id: 10 } });
    const dispatch = vi.fn();
    await actions.updateItem(
      { dispatch },
      { thesisId: 1, id: 10, title: 'Novo título' }
    );
    expect(axios.patch).toHaveBeenCalledWith(
      expect.stringContaining('/theses/1/thesis_items/10'),
      { title: 'Novo título' }
    );
    expect(dispatch).toHaveBeenCalledWith('show', 1);
  });

  it('deleteItem apaga o item e recarrega a tese via show', async () => {
    axios.delete.mockResolvedValue({});
    const dispatch = vi.fn();
    await actions.deleteItem({ dispatch }, { thesisId: 1, id: 10 });
    expect(axios.delete).toHaveBeenCalledWith(
      expect.stringContaining('/theses/1/thesis_items/10')
    );
    expect(dispatch).toHaveBeenCalledWith('show', 1);
  });

  it('reorderItems envia os ids dos itens e recarrega a tese via show', async () => {
    axios.post.mockResolvedValue({ data: [] });
    const dispatch = vi.fn();
    await actions.reorderItems({ dispatch }, { thesisId: 1, ids: [10, 11] });
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('/theses/1/thesis_items/reorder'),
      { ids: [10, 11] }
    );
    expect(dispatch).toHaveBeenCalledWith('show', 1);
  });
});
