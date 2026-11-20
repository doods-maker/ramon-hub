module Current
  thread_mattr_accessor :user
  thread_mattr_accessor :account
  thread_mattr_accessor :account_user
  thread_mattr_accessor :executed_by
  thread_mattr_accessor :contact
  # Import em massa (CSV): silencia os eventos lead/contact por linha —
  # 10k linhas viravam 10k broadcasts + 10k EventDispatcherJobs.
  thread_mattr_accessor :suppress_import_events
  # Importação silenciosa da coexistência (histórico/contatos do WhatsApp Business app): o Dispatcher
  # e os callbacks de mensagem ficam calados — ver Ramon::Silencio.
  thread_mattr_accessor :importacao_silenciosa

  def self.reset
    Current.user = nil
    Current.account = nil
    Current.account_user = nil
    Current.executed_by = nil
    Current.contact = nil
    Current.suppress_import_events = nil
    Current.importacao_silenciosa = nil
  end
end
