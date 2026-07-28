class Ramon::ReuniaoAtaJob < ApplicationJob
  queue_as :low
  retry_on Ramon::LlmClient::TransientError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.marcar_erro(error)
  end

  def perform(reuniao_id)
    @reuniao = Reuniao.find_by(id: reuniao_id)
    return if @reuniao.blank?

    Ramon::ReuniaoAtaService.new(@reuniao).perform
  rescue Ramon::LlmClient::TransientError
    raise
  rescue StandardError => e
    marcar_erro(e)
  end

  def marcar_erro(error)
    @reuniao&.update(status: 'erro', erro: error.message.to_s.first(255))
  end
end
