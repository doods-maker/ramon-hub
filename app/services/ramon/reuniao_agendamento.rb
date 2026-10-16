# Reunião marcada — mesmo efeito venha do Cal.com (webhook) ou do painel do
# lead ("+ Tarefa" → Reunião): tarefa kind meeting, lead anda pra "Reunião
# agendada" (só pra frente), Closer automático, rascunho de confirmação nas
# notas (NUNCA enviado — quem envia é a pessoa), lembretes internos (sino +
# ntfy), atividade e aviso no sino.
# B4.1: cada evento (marcar, remarcar, cancelar) decide UMA vez quem faz (Ramon::Fluxos::Reunioes.assumiu?) e dispara
# o gatilho com essa decisão ('assumido') e os textos prontos. Código no comando: os fluxos ensaiam ANTES (veem o lead
# como estava) e o código faz tudo. Fluxos no comando: o código só dispara (e, no remarcar, move a tarefa).
# Depois dos efeitos, o gatilho sai de novo SEM 'assumido' para os demais fluxos (veem o lead já mexido, como antes).
class Ramon::ReuniaoAgendamento
  # ponytail: fork single-tenant do escritório (Tubarão/SC) — fuso fixo para o
  # texto humano; parametrizar se um dia houver mais contas.
  TIME_ZONE = 'America/Sao_Paulo'.freeze
  DIAS_SEMANA = %w[domingo segunda terça quarta quinta sexta sábado].freeze
  STAGE_LABEL = 'fase-reuniao-agendada'.freeze
  # Prefixo do título da tarefa que veio do Cal.com (o webhook acha por ele).
  CALCOM_PREFIX = 'Reunião Cal.com'.freeze

  # title = nome da reunião (atividade, sino); task_title = título da tarefa
  # (o Cal.com prefixa "Reunião Cal.com:" — o cancel/reschedule acham por ele).
  # automatico: marcada pela IA (Captain) — com RAMON_AGENDA_CONFIRMACAO=on e modo piloto, a confirmação sai sozinha.
  def self.call(lead:, starts_at:, title:, task_title: title, user: nil, formato: 'video', automatico: false) # rubocop:disable Metrics/ParameterLists
    novo = new(lead, starts_at, title, user, formato)
    novo.automatico = automatico
    novo.call(task_title)
  end

  # Confirmação da reunião ao cliente (texto APROVADO 16/10): vira rascunho nas notas (NUNCA enviado) — ou, só se a IA marcou,
  # RAMON_AGENDA_CONFIRMACAO=on e a conversa está em modo piloto, sai direto na conversa (sem o prefixo RASCUNHO).
  def self.confirmar(task, automatico: false)
    lead = task.lead
    texto = confirmacao_texto(task)
    return if automatico && enviar_confirmacao(lead, texto)

    lead.lead_notes.create!(account: lead.account, body: "RASCUNHO (revisar antes de enviar) — confirmação de reunião:
\"#{texto}\"".truncate(1000))
  end

  def self.confirmacao_texto(task)
    convite = Ramon::Agenda::Convite.new(task)
    linha = if task.formato == 'whatsapp' then Ramon::Agenda::Convite::MEIO_WHATSAPP
            elsif task.meet_url.present? then "É por vídeo, neste link: #{task.meet_url}."
            end
    ["Oi #{task.lead.name.to_s.split.first.presence || 'cliente'}! Nossa conversa está confirmada pra #{quando(task.due_at)}.", linha,
     "Pra salvar na sua agenda: #{convite.link_google}",
     'Se não puder comparecer, me avise com antecedência que a gente remarca sem problema.'].compact.join(' ')
  end

  # true se mandou. Chave off (padrão), modo que não é piloto ou lead sem conversa: false → vira rascunho.
  def self.enviar_confirmacao(lead, texto)
    conversa = lead.conversation
    return false unless conversa && chave_confirmacao_on? && Ramon::CopilotoModo.piloto?(Ramon::CopilotoModo.of(conversa))

    conversa.messages.create!(message_type: :outgoing, account_id: conversa.account_id, inbox_id: conversa.inbox_id,
                              sender: conversa.inbox.captain_assistant, content: texto)
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  # ENV direto (padrão dos RAMON_FLUXO_*): GlobalConfigService.load gravaria o default no banco e passaria a ignorar o ENV.
  def self.chave_confirmacao_on? = ENV.fetch('RAMON_AGENDA_CONFIRMACAO', 'off') == 'on'

  # A confirmação de uma reunião marcada pela IA sai sozinha? (chave on + piloto + Google conectado do Closer, o caminho do job)
  def self.envia_sozinha?(lead)
    conversa = lead.conversation
    conversa.present? && chave_confirmacao_on? && Ramon::CopilotoModo.piloto?(Ramon::CopilotoModo.of(conversa)) &&
      lead.closer.present? && GoogleAgendaConta.de(lead.closer).present? && !Ramon::Fluxos::Reunioes.assumiu?(lead.account)
  end

  # Sem colisão na agenda de quem vai receber a reunião (o dono da tarefa; antes de existir, o Closer do lead ou o próximo da fila).
  # Confere só a colisão, não a janela comercial (essa é regra da oferta). Sem dono não há agenda: livre. Remarcando, ignora a própria.
  def self.livre?(lead, inicio, task: nil)
    dono = task&.agenda_user || lead.closer || Ramon::Papeis.proximo(lead.account, Ramon::Papeis::CLOSER)
    dono.nil? || !Ramon::Agenda::Disponibilidade.new(user: dono, account: lead.account).colide?(inicio, ignorar_task_id: task&.id)
  end

  # Remarcar (painel do lead): a mesma reunião em outro horário — lembretes do
  # horário novo (os do antigo viram órfãos e o job descarta), atividade
  # de→para, novo rascunho de confirmação (não enviado) e aviso no sino.
  # formato nil = mantém o da reunião.
  # sem_google: a mudança veio do Google — não empurra de volta (senão o cliente recebe o aviso do Google duas vezes).
  def self.remarcar(task:, starts_at:, user: nil, formato: nil, sem_google: false)
    task.sem_push_google = sem_google
    new(task.lead, starts_at, titulo_de(task), user, formato).remarcar(task)
  end

  # Cancelar (painel do lead): atividade meeting_cancelled, a tarefa sai e sino/ntfy. Os lembretes já
  # enfileirados viram órfãos e o guard do MeetingReminderJob descarta.
  def self.cancelar(task:, user: nil, sem_google: false)
    task.sem_push_google = sem_google
    new(task.lead, task.due_at, titulo_de(task), user).cancelar([task])
  end

  # Cancelar pelo Cal.com: as tarefas Cal.com abertas daquele horário (pode não haver nenhuma).
  def self.cancelar_tarefas(lead:, tarefas:, starts_at:, title:)
    new(lead, starts_at, title, nil).cancelar(tarefas)
  end

  # "Reunião Cal.com: Primeiro Atendimento" → "Primeiro Atendimento"
  def self.titulo_de(task)
    task.title.delete_prefix("#{CALCOM_PREFIX}: ")
  end

  # "quinta, 20/08 às 14:00" — texto único pra sino e rascunho.
  def self.quando(starts_at)
    local = starts_at.in_time_zone(TIME_ZONE)
    "#{DIAS_SEMANA[local.wday]}, #{local.strftime('%d/%m')} às #{local.strftime('%H:%M')}"
  end

  # "Primeiro Atendimento em 20/08/2026 14:00" — to_value da atividade.
  def self.resumo(title, starts_at)
    when_text = starts_at ? starts_at.in_time_zone(TIME_ZONE).strftime('%d/%m/%Y %H:%M') : ''
    "#{title} em #{when_text}".strip.truncate(255)
  end

  attr_writer :automatico

  def initialize(lead, starts_at, title, user, formato = nil)
    @formato = formato
    @lead = lead
    @starts_at = starts_at
    @title = title
    @user = user
  end

  def call(task_title)
    assumido = assumido?
    disparar('reuniao_marcada', dados('marcada', assumido, 'titulo_tarefa' => task_title.truncate(255)))
    efeitos_da_marcacao(task_title) unless assumido
    depois('reuniao_marcada')
    @lead
  end

  # Mover a tarefa é a remarcação em si e fica sempre aqui; o resto é do código ou dos fluxos.
  def remarcar(task)
    de = task.due_at
    task.update!({ due_at: @starts_at, formato: @formato }.compact)
    assumido = assumido?
    disparar('reuniao_marcada', dados('remarcada', assumido, 'resumo_antes' => self.class.resumo(@title, de)))
    efeitos_da_remarcacao(task, de) unless assumido
    Ramon::Fluxos::Reunioes.na_agenda(task, assumido)
    depois('reuniao_marcada')
    task
  end

  def cancelar(tarefas)
    assumido = assumido?
    disparar('reuniao_cancelada', dados('cancelada', assumido, 'tarefa_ids' => tarefas.map(&:id)))
    efeitos_do_cancelamento(tarefas) unless assumido
    depois('reuniao_cancelada')
  end

  private

  def assumido? = Ramon::Fluxos::Reunioes.assumiu?(@lead.account)

  def disparar(gatilho, dados) = Ramon::Fluxos::Disparo.externo(gatilho, @lead, dados)

  # Os demais fluxos (não migrados) desses gatilhos: depois dos efeitos e sem 'assumido', com o mesmo dado de antes.
  def depois(gatilho) = disparar(gatilho, 'quando' => quando_texto)

  def quando_texto = @starts_at ? self.class.quando(@starts_at) : ''

  # O que o gatilho leva: a decisão do evento e os textos prontos, para o fluxo escrever igual ao código.
  def dados(evento, assumido, extra)
    {
      'evento' => evento, 'assumido' => assumido, 'quando' => quando_texto, 'inicio' => @starts_at&.iso8601,
      'titulo' => @title, 'resumo' => self.class.resumo(@title, @starts_at), 'primeiro_nome' => primeiro_nome,
      'quem_marcou_id' => @user&.id, 'formato' => @formato
    }.merge(extra).compact
  end

  def primeiro_nome = @lead.name.to_s.split.first.presence || 'cliente'

  def efeitos_da_marcacao(task_title)
    @lead.lead_activities.create!(account: @lead.account, user: @user, kind: 'meeting_scheduled',
                                  to_value: self.class.resumo(@title, @starts_at))
    task = @lead.lead_tasks.create!(account: @lead.account, user: @user, title: task_title.truncate(255), kind: 'meeting',
                                    due_at: @starts_at, formato: @formato || 'video', confirmacao_automatica: @automatico)
    advance_stage
    Ramon::Papeis.atribuir_closer!(@lead)
    # com conta Google o rascunho nasce no GoogleAgendaPushJob, depois do Meet
    self.class.confirmar(task, automatico: @automatico) unless task.rascunho_no_job?
    enqueue_reminders
    notify('ramon_meeting_scheduled', 'marcada', 'tarefa' => task.title) # a comparação lê a tarefa daqui (a viva pode mudar)
    Ramon::Fluxos::Reunioes.na_agenda(task, false)
  end

  def efeitos_da_remarcacao(task, antes)
    @lead.lead_activities.create!(account: @lead.account, user: @user, kind: 'meeting_rescheduled',
                                  from_value: self.class.resumo(@title, antes), to_value: self.class.resumo(@title, @starts_at))
    self.class.confirmar(task)
    enqueue_reminders
    # sino reaproveita o tipo "reunião marcada" (texto: com o horário novo)
    notify('ramon_meeting_scheduled', 'remarcada')
  end

  def efeitos_do_cancelamento(tarefas)
    @lead.lead_activities.create!(account: @lead.account, user: @user, kind: 'meeting_cancelled',
                                  to_value: self.class.resumo(@title, @starts_at))
    tarefas.each(&:destroy!)
    notify('ramon_meeting_cancelled', 'cancelada', 'tarefa_ids' => tarefas.map(&:id))
  end

  # Sino do hub pra todo mundo da conta + push no celular na hora (o job é
  # no-op sem NTFY_TOPIC); os lembretes têm o seu no MeetingReminderJob.
  # Rastro (Redis) de quem recebeu o sino: a comparação com os fluxos lê dele, não da tabela de avisos.
  def notify(type, verbo, rastro = {})
    quando = quando_texto
    ids = @lead.account.account_users.pluck(:user_id).uniq # os mesmos que o builder avisaria sem user_ids
    Ramon::LeadNotificationBuilder.new(lead: @lead, notification_type: type, user_ids: ids, meta: { 'quando' => quando }).perform
    Ramon::NtfyPushJob.perform_later(@lead.id, title: "Reuniao #{verbo}: #{@lead.name}", body: "#{quando} — #{@title}")
    Ramon::Fluxos::Reunioes.rastro!(@lead.account, { 'tipo' => verbo, 'lead_id' => @lead.id, 'user_ids' => ids,
                                                     'inicio' => @starts_at&.iso8601 }.merge(rastro).compact)
  end

  # Nunca regride: quem já está em Negociação e remarcou fica onde está.
  def advance_stage
    stage = @lead.account.lead_stages.find_by(label: STAGE_LABEL)
    return if stage.blank? || @lead.lead_stage.position >= stage.position

    @lead.update!(lead_stage: stage)
  end

  # Lembretes anti no-show: só offsets ainda no futuro; cancel/reschedule não
  # desagenda — o guard do job mata o lembrete órfão.
  def enqueue_reminders
    Ramon::MeetingReminderJob::OFFSETS.each do |offset, label|
      fire_at = @starts_at - offset
      next if fire_at.past?

      Ramon::MeetingReminderJob.set(wait_until: fire_at).perform_later(@lead.id, @starts_at.iso8601, label)
    end
  end
end
