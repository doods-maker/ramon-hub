import ApiClient from './ApiClient';

class RamonPrescriptionRadarAPI extends ApiClient {
  constructor() {
    super('ramon_prescription_radar', { accountScoped: true });
  }
}

export default new RamonPrescriptionRadarAPI();
