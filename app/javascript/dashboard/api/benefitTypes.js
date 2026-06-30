/* global axios */
import ApiClient from './ApiClient';

class BenefitTypesAPI extends ApiClient {
  constructor() {
    super('benefit_types', { accountScoped: true });
  }

  reorder(ids) {
    return axios.post(`${this.url}/reorder`, { ids });
  }
}

export default new BenefitTypesAPI();
