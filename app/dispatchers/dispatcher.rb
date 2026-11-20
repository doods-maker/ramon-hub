class Dispatcher
  include Singleton

  attr_reader :async_dispatcher, :sync_dispatcher

  def self.dispatch(event_name, timestamp, data, async = false)
    Rails.configuration.dispatcher.dispatch(event_name, timestamp, data, async)
  end

  def initialize
    @sync_dispatcher = SyncDispatcher.new
    @async_dispatcher = AsyncDispatcher.new
  end

  def dispatch(event_name, timestamp, data, _async = false)
    # FORK-PONTO (ramon): importação silenciosa da coexistência — nenhum listener ouve (lead, fluxo, IA, automação,
    # webhook, notificação, ActionCable, relatório, campanha, CSAT). Ver Ramon::Silencio.
    return if Current.importacao_silenciosa

    @sync_dispatcher.dispatch(event_name, timestamp, data)
    @async_dispatcher.dispatch(event_name, timestamp, data)
  end

  def load_listeners
    @sync_dispatcher.load_listeners
    @async_dispatcher.load_listeners
  end
end
