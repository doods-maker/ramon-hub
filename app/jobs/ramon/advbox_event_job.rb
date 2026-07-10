class Ramon::AdvboxEventJob < ApplicationJob
  queue_as :low

  def perform(event_id)
    event = AdvboxEvent.find_by(id: event_id)
    return if event.blank?

    Ramon::AdvboxEventProcessor.new(event).perform
  rescue StandardError => e
    # best-effort: o payload cru fica guardado p/ replay; não derruba a fila
    event&.update(status: 'error', note: "#{e.class}: #{e.message}".truncate(255))
    Rails.logger.warn("AdvboxEventJob falhou p/ evento #{event_id}: #{e.class} #{e.message}")
  end
end
