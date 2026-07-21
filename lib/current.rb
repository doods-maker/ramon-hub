module Current
  thread_mattr_accessor :user
  thread_mattr_accessor :account
  thread_mattr_accessor :account_user
  thread_mattr_accessor :executed_by
  thread_mattr_accessor :contact
  # Import em massa (CSV): silencia os eventos lead/contact por linha —
  # 10k linhas viravam 10k broadcasts + 10k EventDispatcherJobs.
  thread_mattr_accessor :suppress_import_events

  def self.reset
    Current.user = nil
    Current.account = nil
    Current.account_user = nil
    Current.executed_by = nil
    Current.contact = nil
    Current.suppress_import_events = nil
  end
end
