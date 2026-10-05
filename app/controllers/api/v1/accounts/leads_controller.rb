class Api::V1::Accounts::LeadsController < Api::V1::Accounts::BaseController
  ASSIGNMENT_KEYS = %w[sdr_id closer_id].freeze

  before_action :current_account
  before_action :fetch_lead, except: [:index, :create, :for_conversation, :encaminhar_comercial]
  before_action :check_authorization

  def index
    @leads = filtered_leads
  end

  def show; end

  def create
    existing = duplicate_open_lead
    if existing
      render json: { error: 'DUPLICATE_LEAD', existing: existing.push_event_data }, status: :conflict
      return
    end

    attrs = gestor? ? permitted_params : permitted_params.except(*ASSIGNMENT_KEYS)
    @lead = Current.account.leads.create!(attrs)
  end

  def update
    ensure_lost_reason!
    ensure_assignment_permission! unless performed?
    return if performed?

    @lead.update!(merged_params)
  end

  def destroy
    @lead.destroy!
    head :ok
  end

  # Portal do cliente: gera (ou reusa) o token e devolve a URL pública completa.
  def portal_link
    render json: { url: "#{ENV.fetch('FRONTEND_URL', '')}/portal/#{@lead.ensure_portal_token!}" }
  end

  # Retomada W4 sob demanda (Onda D): botão "Preparar retomada" do painel.
  # Resultado (nota RASCUNHO + tarefa) chega pelos broadcasts de sempre.
  def follow_up_draft
    Ramon::FollowUpDraftJob.perform_later(@lead.id)
    head :accepted
  end

  # Closer registra a reunião: qualificada ou não (base do prêmio do SDR).
  def reuniao
    resultado = params[:resultado].to_s
    return render json: { error: 'RESULTADO_INVALIDO' }, status: :unprocessable_entity unless Lead::REUNIAO_RESULTADOS.include?(resultado)

    @lead.registrar_reuniao!(resultado, Current.user)
    render :show
  end

  def for_conversation
    # o front manda o id do objeto de conversa da SPA, que é o display_id (por conta)
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    # readonly: só consulta (banner da conversa) — nunca cria nem adota lead.
    # Caixa com Portaria (setores do escritório) também nunca cria lead ao abrir:
    # lead lá só nasce pelo "Encaminhar ao comercial".
    readonly = params[:readonly] || conversation.inbox.portaria_enabled?
    @lead = readonly ? find_readonly_lead_for(conversation) : find_or_create_lead_for(conversation)
    return head :no_content if @lead.nil?

    authorize(@lead, :show?)
  end

  # Portaria: a Recepção manda um lead orgânico pro comercial — time Comercial + lead no funil.
  def encaminhar_comercial
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    conversation.update!(team: Current.account.teams.find_by!(name: 'comercial'))
    @lead = find_or_create_lead_for(conversation)
    # quem chega sem anúncio presume-se indicado (glossário: Indicação); não pisa em canal já derivado
    @lead.update!(channel: 'indicacao') if @lead.channel == 'outro'
    authorize(@lead, :show?)
    render :for_conversation
  end

  private

  # reuniao? depende do lead (quem é o Closer dele) — o resto autoriza pela classe.
  def check_authorization
    super(action_name == 'reuniao' ? @lead : nil)
  end

  def find_readonly_lead_for(conversation)
    lead = Current.account.leads.find_by(conversation_id: conversation.id)
    return lead if lead
    return if conversation.contact_id.blank?

    Current.account.leads.open.find_by(contact_id: conversation.contact_id)
  end

  def find_or_create_lead_for(conversation)
    lead = Current.account.leads.find_by(conversation_id: conversation.id)
    return lead if lead

    lead = find_lead_for_contact(conversation)
    return lead if lead

    create_lead_for(conversation)
  end

  def find_lead_for_contact(conversation)
    return if conversation.contact_id.blank?

    lead = Current.account.leads.open.find_by(contact_id: conversation.contact_id)
    return if lead.blank?

    lead.update!(conversation_id: conversation.id) if lead.conversation_id != conversation.id
    lead
  end

  # Dedup por telefone na criação manual: o front resolve o contato pelo
  # telefone antes do create, então mesmo telefone == mesmo contact_id.
  # `force` presente = usuário confirmou "criar mesmo assim" após o 409.
  def duplicate_open_lead
    return if params[:force].present? || permitted_params[:contact_id].blank?

    Current.account.leads.open.find_by(contact_id: permitted_params[:contact_id])
  end

  def fetch_lead
    @lead = Current.account.leads.find(params[:id])
  end

  def filtered_leads
    # includes mata o N+1 do índice do Kanban: o partial toca 7 belongs_to +
    # lead_triages (latest_triage) + thesis_items (docs_counts) por lead. Sem
    # isto, board de N leads = ~10N SELECTs.
    leads = policy_scope(Current.account.leads)
            .includes(:lead_stage, :benefit_type, :lead_priority, { thesis: :thesis_items }, :sdr, :closer, :contact,
                      :lead_triages, :lead_tasks, { conversation: :inbox })
    # Caso de cálculo só aparece nas visões por pessoa (Cálculos, gaveta, Linha da Vida).
    leads = leads.funil if params[:contact_id].blank?
    leads = apply_equality_filters(leads)
    leads = leads.where('sdr_id = :a OR closer_id = :a', a: params[:agent_id]) if params[:agent_id].present?
    leads = apply_cadence_filters(apply_period_filters(leads))
    leads = search_leads(leads, params[:q]) if params[:q].present?
    leads
  end

  def apply_equality_filters(leads)
    %i[benefit_type_id lead_priority_id lead_stage_id source channel contact_id].each do |key|
      leads = leads.where(key => params[key]) if params[key].present?
    end
    leads
  end

  def apply_period_filters(leads)
    leads = leads.where(created_at: Date.parse(params[:created_after]).beginning_of_day..) if params[:created_after].present?
    leads = leads.where(created_at: ..Date.parse(params[:created_before]).end_of_day) if params[:created_before].present?
    leads
  end

  def apply_cadence_filters(leads)
    leads = Ramon::Cadencia.parados(leads) if params[:stalled].present?
    leads = leads.where.not(id: Current.account.lead_tasks.open_tasks.select(:lead_id)) if params[:no_open_task].present?
    Ramon::LeadRadar.kpi_filters(Current.account, leads, params)
  end

  def ensure_lost_reason!
    target_stage_id = permitted_params[:lead_stage_id]
    return if target_stage_id.blank?

    stage = Current.account.lead_stages.find_by(id: target_stage_id)
    return unless stage&.is_lost
    return if permitted_params[:lost_reason].presence || @lead.lost_reason.presence

    render json: { error: 'LOST_REASON_REQUIRED' }, status: :unprocessable_entity
  end

  # Papéis (playbook §13): só o gestor troca SDR/Closer — o normal é a atribuição automática.
  def ensure_assignment_permission!
    return if gestor?
    return if ASSIGNMENT_KEYS.none? { |key| permitted_params.key?(key) && permitted_params[key].to_s != @lead[key].to_s }

    render json: { error: 'ASSIGNMENT_FORBIDDEN' }, status: :forbidden
  end

  def gestor?
    Current.account_user&.administrator?
  end

  # Telefone é gravado em E.164 (+5548998123456): "(48) 99812-3456" só casa
  # pelos dígitos. Com 8+ dígitos a busca também compara só os números.
  def search_leads(leads, query)
    conditions = ['leads.name ILIKE :q', 'contacts.name ILIKE :q', 'contacts.phone_number ILIKE :q']
    digits = query.to_s.delete('^0-9')
    conditions << 'contacts.phone_number LIKE :digits' if digits.length >= 8
    leads.left_joins(:contact).where(conditions.join(' OR '), q: "%#{query}%", digits: "%#{digits}%")
  end

  def create_lead_for(conversation)
    Current.account.leads.create!(
      conversation: conversation,
      contact: conversation.contact,
      lead_stage: default_lead_stage,
      name: lead_name_for(conversation)
    )
  end

  def default_lead_stage
    Current.account.lead_stages.order(:position).first
  end

  def lead_name_for(conversation)
    contact = conversation.contact
    contact&.name.presence || contact&.phone_number.presence || contact&.identifier.presence || "Lead ##{conversation.display_id}"
  end

  def permitted_params
    params.permit(:name, :lead_stage_id, :benefit_type_id, :lead_priority_id, :thesis_id,
                  :contact_id, :conversation_id, :sdr_id, :closer_id,
                  :position, :lost_reason, :value, :source, :channel, :dcb_em, :benefit_monthly_value,
                  custom_attributes: {})
  end

  # PATCH parcial de custom_attributes: o cliente pode mandar só a chave que
  # mudou (checklists) sem apagar as demais (colheita/advbox/zapsign) — o merge
  # da base atual acontece AQUI, não no cliente (que pode ter um record slim).
  def merged_params
    attrs = permitted_params.to_h
    attrs = mark_valor_manual(attrs) if attrs['value'].present?
    return attrs if attrs['custom_attributes'].nil?

    attrs.merge('custom_attributes' => @lead.custom_attributes.to_h.deep_merge(attrs['custom_attributes'].to_h))
  end

  # Onda 3 (LeadValorEstimado): PATCH com :value é mão humana editando
  # o campo — grava a flag de origem manual pro before_save nunca mais pisar
  # nesse valor. Deep-merge aqui (não substitui) pra não apagar custom_attributes
  # que o cliente tenha mandado junto no mesmo PATCH.
  def mark_valor_manual(attrs)
    flag = { 'valor_estimado' => { 'origem' => 'manual', 'em' => Time.zone.now.iso8601 } }
    attrs.merge('custom_attributes' => (attrs['custom_attributes'] || {}).to_h.deep_merge(flag))
  end
end
