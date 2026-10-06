# KPIs do SDR no Painel do time (operação comercial, doc 04 §4). O lead é do
# SDR que está nele agora (leads.sdr_id), como no extrato da variável.
class Ramon::PainelTimeSdr < Ramon::PainelTimeBase
  ETAPA_QUALIFICACAO = 'fase-qualificacao'.freeze
  # Perdido por estes motivos (seed de motivos de perda) não é qualificado.
  MOTIVOS_SEM_QUALIFICACAO = ['Sem viabilidade', 'Fora da área'].freeze
  LIMITE_SEM_RESPOSTA = 60 # minutos em horário comercial
  REGISTRO_NO_DIA_SQL = <<~SQL.squish.freeze
    EXISTS (SELECT 1 FROM lead_activities rc WHERE rc.lead_id = leads.id AND rc.kind = 'registro_completo'
      AND DATE(rc.created_at AT TIME ZONE 'UTC' AT TIME ZONE :zona) = DATE(leads.created_at AT TIME ZONE 'UTC' AT TIME ZONE :zona))
  SQL

  def kpis
    {
      primeira_resposta: primeira_resposta, sem_resposta: sem_resposta, qualificado_agendada: qualificado_agendada,
      show: show, nao_qualificada: nao_qualificada, registro_completo: registro_completo
    }
  end

  # Leads recebidos por dia (criação do lead, fuso de SP).
  def volume
    serie(dos_sdrs.group_by_day(:created_at, time_zone: TIME_ZONE, range: periodo).count)
  end

  def meta_extra(_mes)
    {}
  end

  private

  def dos_sdrs
    leads.where(sdr_id: ids)
  end

  # Mediana, em minutos de horário comercial, da 1ª resposta humana na
  # conversa do lead (reporting_events first_response: event_start_time →
  # event_end_time), das respostas cuja espera começou no período.
  def primeira_resposta
    tempos = ReportingEvent.where(account_id: account.id, name: 'first_response', event_start_time: periodo,
                                  conversation_id: dos_sdrs.select(:conversation_id))
                           .pluck(:event_start_time, :event_end_time)
                           .map { |inicio, fim| Ramon::HorarioComercial.minutos_entre(inicio, fim) }
    { valor: mediana(tempos), num: tempos.size, den: nil }
  end

  # Agora (ignora o período): conversa aberta do lead, em caixa de lead, sem
  # 1ª resposta, esperando há mais de 60 minutos de horário comercial.
  def sem_resposta
    agora = Time.current
    esperando = account.conversations.open.joins(:inbox)
                       .where(inboxes: { auto_create_lead: true }, first_reply_created_at: nil)
                       .where(id: dos_sdrs.select(:conversation_id)).pluck(:created_at)
    atrasadas = esperando.count { |desde| Ramon::HorarioComercial.minutos_entre(desde, agora) > LIMITE_SEM_RESPOSTA }
    { valor: atrasadas, num: atrasadas, den: esperando.size }
  end

  # Coorte: leads qualificados criados no período; agendada = tem meeting_scheduled.
  def qualificado_agendada
    base = qualificados
    taxa(base.where(id: atividades('meeting_scheduled').select(:lead_id)).count, base.count)
  end

  # Qualificado = chegou à etapa "Qualificação" ou a uma posterior (posição ≥,
  # etapa não perdida) — está nela agora ou passou por ela (stage_changed, pelo
  # nome da etapa) — e não foi perdido por "Sem viabilidade" ou "Fora da área".
  def qualificados
    posicao = account.lead_stages.find_by(label: ETAPA_QUALIFICACAO)&.position
    return leads.none if posicao.nil?

    etapas = account.lead_stages.where(is_lost: false).where(position: posicao..)
    coorte = dos_sdrs.where(created_at: periodo)
    coorte.where(lead_stage_id: etapas.select(:id))
          .or(coorte.where(id: atividades('stage_changed').where(to_value: etapas.select(:name)).select(:lead_id)))
          .where('leads.lost_reason IS NULL OR leads.lost_reason NOT IN (?)', MOTIVOS_SEM_QUALIFICACAO)
  end

  # Show = realizadas ÷ (realizadas + faltas), no período. Realizada = lead com
  # reuniao_registrada (correção do resultado não conta 2x); falta = cada
  # meeting_no_show. Reunião cancelada é apagada e não entra na conta.
  def show
    dos_leads = dos_sdrs.select(:id)
    realizadas = atividades('reuniao_registrada').where(created_at: periodo, lead_id: dos_leads).distinct.count(:lead_id)
    faltas = atividades('meeting_no_show').where(created_at: periodo, lead_id: dos_leads).count
    taxa(realizadas, realizadas + faltas)
  end

  # Reuniões com resultado (por reuniao_registrada_em) marcadas "não qualificada".
  def nao_qualificada
    reunioes = dos_sdrs.where(reuniao_registrada_em: periodo).where.not(reuniao_resultado: nil)
    taxa(reunioes.where(reuniao_resultado: 'nao_qualificada').count, reunioes.count)
  end

  # Leads criados no período cuja atividade registro_completo caiu no mesmo
  # dia (SP) da criação (Ramon::RegistroCompleto — só existe daqui pra frente).
  def registro_completo
    coorte = dos_sdrs.where(created_at: periodo)
    taxa(coorte.where(REGISTRO_NO_DIA_SQL, zona: TIME_ZONE).count, coorte.count)
  end
end
