import ApiClient from './ApiClient';

class RamonWatchdogAPI extends ApiClient {
  constructor() {
    super('ramon_watchdog', { accountScoped: true });
  }
}

export default new RamonWatchdogAPI();
