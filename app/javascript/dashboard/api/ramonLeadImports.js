/* global axios */
import ApiClient from './ApiClient';

class RamonLeadImportsAPI extends ApiClient {
  constructor() {
    super('ramon_lead_imports', { accountScoped: true });
  }

  create(file) {
    const formData = new FormData();
    formData.append('import_file', file);
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new RamonLeadImportsAPI();
