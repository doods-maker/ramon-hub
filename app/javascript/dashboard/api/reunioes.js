/* global axios */
import ApiClient from './ApiClient';

class ReunioesAPI extends ApiClient {
  constructor() {
    super('ramon_reunioes', { accountScoped: true });
  }

  criar(formData, onUploadProgress) {
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
      onUploadProgress,
    });
  }

  reprocessar(id) {
    return axios.post(`${this.url}/${id}/reprocessar`);
  }
}

export default new ReunioesAPI();
