import ApiClient from '../ApiClient';

class CaptainFerramentas extends ApiClient {
  constructor() {
    super('captain/ferramentas', { accountScoped: true });
  }
}

export default new CaptainFerramentas();
