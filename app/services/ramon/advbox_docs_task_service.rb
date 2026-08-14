# Pacote de documentos completo no Drive → tarefa no ADVBOX pra controller
# fazer o upload manual (ADR-0002). Sem envs, no-op.
class Ramon::AdvboxDocsTaskService
  def initialize(lead)
    @lead = lead
  end

  def perform
    return unless configurado?
    return if ja_criada?
    return Rails.logger.warn("[Ramon::AdvboxDocsTaskService] lead=#{@lead.id} sem lawsuit no advbox") if lawsuit_id.blank?

    gravar(Ramon::AdvboxClient.create_post(payload))
  rescue Ramon::AdvboxClient::RequestError => e
    Rails.logger.warn("[Ramon::AdvboxDocsTaskService] lead=#{@lead.id} advbox recusou: #{e.code}")
  end

  private

  def controller_id = ENV.fetch('RAMON_ADVBOX_CONTROLLER_ID', nil)

  def task_type_id = ENV.fetch('RAMON_ADVBOX_DOCS_TASK_ID', nil)

  def lawsuit_id = @lead.custom_attributes&.dig('advbox', 'lawsuits_id')

  def configurado?
    controller_id.present? && task_type_id.present? && ENV.fetch('ADVBOX_API_TOKEN', nil).present?
  end

  def ja_criada?
    @lead.custom_attributes&.dig('drive', 'advbox_task_id').present?
  end

  def payload
    {
      from: controller_id.to_s, guests: [controller_id.to_i],
      tasks_id: task_type_id.to_s, lawsuits_id: lawsuit_id.to_s,
      start_date: Time.zone.today.iso8601,
      comments: "Checklist de documentos completo — #{itens_no_drive} arquivo(s) no Drive " \
                "(pasta \"#{pasta}\") — subir ao ADVBOX e apagar o atalho do dia. Lead ##{@lead.id}."
    }
  end

  def pasta
    nome = (@lead.contact&.name.presence || @lead.name).to_s.strip
    cpf = @lead.contact&.cpf
    "#{[nome, cpf.presence].compact.join(' — ')} — COMPLETO"
  end

  def itens_no_drive
    @lead.custom_attributes&.dig('drive', 'itens')&.size.to_i
  end

  def gravar(resp)
    @lead.reload
    drive = (@lead.custom_attributes&.dig('drive') || {}).merge('advbox_task_id' => resp&.dig('posts_id') || true)
    @lead.update!(custom_attributes: @lead.custom_attributes.to_h.merge('drive' => drive))
  end
end
