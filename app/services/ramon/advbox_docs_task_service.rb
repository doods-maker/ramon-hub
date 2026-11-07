# Tarefas do hub no ADVBOX quando a pasta de documentos do caso fecha:
# - perform: tarefa de upload manual para a controller (ADR-0002). Sem as envs, no-op.
# - analise_do_caso: a ANÁLISE DO CASO (spec Etapa Documentos §8), no processo que o Ganho abriu, para o Eduardo enquanto a
#   esteira está em teste, com o caminho da pasta da tese nas notas (a Recepção da esteira lê dali). Uma por caso: o id fica em
#   advbox.analise_posts_id assim que a tarefa nasce (padrão step do AdvboxClosingService); ADVBOX fora do ar sobe o erro para
#   o retry do job, que não duplica.
class Ramon::AdvboxDocsTaskService
  ANALISE_TASK_ID = 8_745_386 # ANÁLISE DO CASO
  # Só a sub-chave, num UPDATE: o resto do custom_attributes (gravado em paralelo por outros jobs) fica como está.
  GRAVAR_ANALISE = "custom_attributes = jsonb_set(COALESCE(custom_attributes, '{}'::jsonb), '{advbox}', " \
                   "COALESCE(custom_attributes -> 'advbox', '{}'::jsonb) || jsonb_build_object('analise_posts_id', ?::jsonb))".freeze
  TRAVA = 120 # s; quem chama junto (passagem ao Jurídico e fim do Ganho no ADVBOX) espera a vez do outro

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

  # @return [Symbol] :criada, :ja_criada, :sem_caso (o Ganho não abriu o processo), :sem_token, :recusada (4xx) ou :ocupada
  def analise_do_caso
    return :sem_token if ENV.fetch('ADVBOX_API_TOKEN', nil).blank?
    return :ja_criada if analise_criada?
    return :sem_caso if lawsuit_id.blank?

    com_trava { analise_criada? ? :ja_criada : criar_analise }
  rescue Ramon::AdvboxClient::RequestError => e
    Rails.logger.warn("[Ramon::AdvboxDocsTaskService] lead=#{@lead.id} ANÁLISE DO CASO recusada: #{e.code}")
    :recusada
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

  def analise_criada? = @lead.custom_attributes&.dig('advbox', 'analise_posts_id').present?

  # ponytail: trava no Redis (como o rascunho do AvisoDaIa); some no fim ou em TRAVA s se o processo morrer no meio.
  def com_trava
    chave = "RAMON::ANALISE_DO_CASO::#{@lead.id}"
    return :ocupada unless Redis::Alfred.set(chave, 1, nx: true, ex: TRAVA)

    begin
      @lead.reload
      yield
    ensure
      Redis::Alfred.delete(chave)
    end
  end

  def criar_analise
    id = Ramon::AdvboxClient.create_post(payload_analise)&.dig('posts_id')
    Lead.unscoped.where(id: @lead.id).update_all([GRAVAR_ANALISE, (id || true).to_json]) # rubocop:disable Rails/SkipsModelValidations
    @lead.reload
    :criada
  end

  def payload_analise
    responsavel = Ramon::AdvboxClosingService::USERS_ID
    {
      from: responsavel.to_s, guests: [responsavel], tasks_id: ANALISE_TASK_ID.to_s, lawsuits_id: lawsuit_id.to_s,
      start_date: Time.zone.today.iso8601,
      comments: "Documentos completos no hub (lead ##{@lead.id}). Pasta da tese no Drive: #{pasta}"
    }
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

  def pasta = Ramon::DriveExportService.new(@lead).caminho_completo

  def itens_no_drive
    @lead.custom_attributes&.dig('drive', 'itens')&.size.to_i
  end

  def gravar(resp)
    @lead.reload
    drive = (@lead.custom_attributes&.dig('drive') || {}).merge('advbox_task_id' => resp&.dig('posts_id') || true)
    @lead.update!(custom_attributes: @lead.custom_attributes.to_h.merge('drive' => drive))
  end
end
