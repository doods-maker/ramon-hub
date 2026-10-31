class AsyncDispatcher < BaseDispatcher
  def dispatch(event_name, timestamp, data)
    EventDispatcherJob.perform_later(event_name, timestamp, data)
  end

  def publish_event(event_name, timestamp, data)
    event_object = Events::Base.new(event_name, timestamp, data)
    return publish_equipe(event_object) if Ramon::Equipe.evento?(data)

    publish(event_object.method_name, event_object)
  end

  # ramon: na caixa Equipe (chat interno) o hub fica surdo — lead, fluxo, agente, IA, automação, webhook, CSAT,
  # relatório. Só o aviso nativo de mensagem a quem participa (NotificationListener) ouve o evento (ADR 0011).
  def publish_equipe(event_object)
    listener = NotificationListener.instance
    listener.public_send(event_object.method_name, event_object) if listener.respond_to?(event_object.method_name)
  end

  def listeners
    [
      AutomationRuleListener.instance,
      CampaignListener.instance,
      CsatSurveyListener.instance,
      HookListener.instance,
      InstallationWebhookListener.instance,
      NotificationListener.instance,
      ParticipationListener.instance,
      Conversations::UnreadCounts::Listener.instance,
      ReportingEventListener.instance,
      WebhookListener.instance,
      RamonLeadListener.instance,
      RamonAgenteListener.instance,
      RamonFluxoListener.instance
    ]
  end
end

AsyncDispatcher.prepend_mod_with('AsyncDispatcher')
