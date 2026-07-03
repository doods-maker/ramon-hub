/* global axios */
import ApiClient from './ApiClient';

class ThesesAPI extends ApiClient {
  constructor() {
    super('theses', { accountScoped: true });
  }

  reorder(ids) {
    return axios.post(`${this.url}/reorder`, { ids });
  }

  createItem(thesisId, data) {
    return axios.post(`${this.url}/${thesisId}/thesis_items`, data);
  }

  updateItem(thesisId, itemId, data) {
    return axios.patch(`${this.url}/${thesisId}/thesis_items/${itemId}`, data);
  }

  deleteItem(thesisId, itemId) {
    return axios.delete(`${this.url}/${thesisId}/thesis_items/${itemId}`);
  }

  reorderItems(thesisId, ids) {
    return axios.post(`${this.url}/${thesisId}/thesis_items/reorder`, {
      ids,
    });
  }
}

export default new ThesesAPI();
