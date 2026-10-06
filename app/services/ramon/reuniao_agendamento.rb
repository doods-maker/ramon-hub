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
  def self.call(lead:, starts_at:, title:, task_title: title, user: nil)
    new(lead, starts_at, title, user).call(task_title)
  end

  # Remarcar (painel do lead): a mesma reunião em outro horário — lembretes do
  # horário novo (os do antigo viram órfãos e o job descarta), atividade
  # de→para, novo rascunho de confirmação (não enviado) e aviso no sino.
  def self.remarcar(task:, starts_at:, user: nil)
    new(task.lead, starts_at, titulo_de(task), user).remarcar(task)
  end

  # Cancelar (painel do lead): atividade meeting_cancelled, a tarefa sai e sino/ntfy. Os lembretes já
  # enfileirados viram órfãos e o guard do MeetingReminderJob descarta.
  def self.cancelar(task:, user: nil)
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

  def initialize(lead, starts_at, title, user)
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
    task.update!(due_at: @starts_at)
    assumido = assumido?
    disparar('reuniao_marcada', dados('remarcada', assumido, 'resumo_antes' => self.class.resumo(@title, de)))
    efeitos_da_remarcacao(de) unless assumido
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
      'quem_marcou_id' => @user&.id
    }.merge(extra).compact
  end

  def primeiro_nome = @lead.name.to_s.split.first.presence || 'cliente'

  def efeitos_da_marcacao(task_title)
    @lead.lead_activities.create!(account: @lead.account, user: @user, kind: 'meeting_scheduled',
                                  to_value: self.class.resumo(@title, @starts_at))
    task = @lead.lead_tasks.create!(account: @lead.account, user: @user, title: task_title.truncate(255), kind: 'meeting',
                                    due_at: @starts_at)
    advance_stage
    Ramon::Papeis.atribuir_closer!(@lead)
    confirmation_draft
    enqueue_reminders
    notify('ramon_meeting_scheduled', 'marcada')
    Ramon::Fluxos::Reunioes.na_agenda(task, false)
  end

  def efeitos_da_remarcacao(antes)
    @lead.lead_activities.create!(account: @lead.account, user: @user, kind: 'meeting_rescheduled',
                                  from_value: self.class.resumo(@title, antes), to_value: self.class.resumo(@title, @starts_at))
    confirmation_draft
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

  # Rascunho de confirmação (gatilho do compromisso) — estático, sem LLM. O fluxo "Reunião marcada" copia este texto.
  def confirmation_draft
    @lead.lead_notes.create!(account: @lead.account, body: <<~NOTA.strip.truncate(1000))
      RASCUNHO (revisar antes de enviar) — confirmação de reunião:
      "Oi #{primeiro_nome}! Nossa conversa está confirmada pra #{self.class.quando(@starts_at)}. Vou te esperar, tá? Se não puder comparecer, me avise com antecedência que a gente remarca sem problema."
    NOTA
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
