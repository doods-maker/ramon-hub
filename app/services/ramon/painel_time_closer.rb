# KPIs do Closer no Painel do time (operação comercial, doc 04 §4). O lead é
# do Closer que está nele agora (leads.closer_id). KPI com prazo (7 dias, 24h,
# 48h): quem ainda está dentro do prazo só entra no denominador se já cumpriu —
# o contrato de ontem não derruba o % de hoje.
class Ramon::PainelTimeCloser < Ramon::PainelTimeBase
  DOCS_7D_SQL = "leads.docs_completos_em <= leads.won_at + interval '7 days'".freeze
  DOSSIE_24H_SQL = <<~SQL.squish.freeze
    EXISTS (SELECT 1 FROM lead_activities de WHERE de.lead_id = leads.id AND de.kind = 'dossie_entregue'
      AND de.created_at <= leads.won_at + interval '24 hours')
  SQL
  # Painel do Cliente entregue = o cliente AdvBox do lead tem convite no portal.
  PAINEL_SQL = <<~SQL.squish.freeze
    EXISTS (SELECT 1 FROM portal_clientes pc WHERE pc.account_id = leads.account_id AND pc.convidado_em IS NOT NULL
      AND pc.advbox_customer_id::text = leads.custom_attributes->'advbox'->>'customers_id')
  SQL
  # Retomada do "vou pensar": mensagem de saída não privada da equipe na
  # conversa do lead, ou tarefa follow_up criada, em até 48h depois da marca.
  RETOMADA_SQL = <<~SQL.squish.freeze
    EXISTS (SELECT 1 FROM messages m JOIN leads l ON l.conversation_id = m.conversation_id
      WHERE l.id = lead_activities.lead_id AND m.message_type = 1 AND m.private = false AND m.sender_type = 'User'
      AND m.created_at > lead_activities.created_at AND m.created_at <= lead_activities.created_at + interval '48 hours')
    OR EXISTS (SELECT 1 FROM lead_tasks t WHERE t.lead_id = lead_activities.lead_id AND t.kind = 'follow_up'
      AND t.created_at > lead_activities.created_at AND t.created_at <= lead_activities.created_at + interval '48 hours')
  SQL
  ASSINADO_EM_SQL = "leads.custom_attributes->'zapsign'->>'assinado_em'".freeze

  def kpis
    {
      conversao: conversao, assinado_na_reuniao: assinado_na_reuniao, docs_7d: docs_7d, cancelamento_7d: cancelamento_7d,
      painel: painel, dossie_24h: dossie_24h, vou_pensar_48h: vou_pensar_48h
    }
  end

  # Contratos (ganhos) por semana — semana começando na segunda, fuso de SP.
  def volume
    serie(dos_closers.group_by_week(:won_at, time_zone: TIME_ZONE, week_start: :monday, range: periodo).count)
  end

  # Fechados no mês que ainda não viraram contrato limpo (docs / 7 dias).
  def meta_extra(mes)
    { aguardando: dos_closers.where(won_at: mes, contrato_limpo_em: nil).count }
  end

  private

  def dos_closers
    leads.where(closer_id: ids)
  end

  def ganhos
    dos_closers.where(won_at: periodo)
  end

  # Coorte: reuniões registradas como qualificadas no período; contrato = ganho.
  def conversao
    coorte = dos_closers.where(reuniao_registrada_em: periodo, reuniao_resultado: 'qualificada')
    taxa(coorte.where.not(won_at: nil).count, coorte.count)
  end

  # Regra: assinado na própria reunião = o dia (SP) da assinatura —
  # custom_attributes.zapsign.assinado_em, ou won_at quando não houver — é o
  # dia da reunião. Dia da reunião = due_at da última tarefa meeting concluída
  # do lead; sem ela, reuniao_registrada_em. Ganho sem reunião conhecida fica fora.
  def assinado_na_reuniao
    linhas = ganhos.pluck(:id, :won_at, :reuniao_registrada_em, Arel.sql(ASSINADO_EM_SQL))
    reunioes = LeadTask.where(lead_id: linhas.map(&:first), kind: 'meeting').where.not(completed_at: nil).group(:lead_id).maximum(:due_at)
    pares = linhas.filter_map do |id, won_at, registrada_em, assinado_em|
      reuniao = reunioes[id] || registrada_em
      [dia(assinado_em || won_at), dia(reuniao)] if reuniao
    end
    taxa(pares.count { |assinado, reuniao| assinado == reuniao }, pares.size)
  end

  # Ganhos do período com a checklist completa até 7 dias depois do ganho.
  def docs_7d
    no_prazo(DOCS_7D_SQL, 7.days)
  end

  # Ganhos do período com "Dossiê entregue" até 24h depois do ganho.
  def dossie_24h
    no_prazo(DOSSIE_24H_SQL, 24.hours)
  end

  def no_prazo(cumpriu_sql, prazo)
    cumpriram = ganhos.where(cumpriu_sql)
    taxa(cumpriram.count, ganhos.where(won_at: ...prazo.ago).or(cumpriram).count)
  end

  # Contrato que saiu de Fechado até 7 dias depois do ganho, pela atividade
  # contrato_cancelado (guarda o won_at antigo; só existe daqui pra frente).
  # Coorte = ganhos do período (pelo won_at antigo, nos cancelados) com os 7
  # dias vencidos, mais os já cancelados.
  def cancelamento_7d
    cancelados = cancelados_no_periodo
    em_7d = cancelados.filter_map { |id, ganho, em| id if em <= ganho + 7.days }
    coorte = ganhos.where(won_at: ...7.days.ago).pluck(:id) | cancelados.map(&:first)
    taxa(em_7d.uniq.size, coorte.size)
  end

  def cancelados_no_periodo
    atividades('contrato_cancelado').where(lead_id: dos_closers.select(:id)).where.not(from_value: nil)
                                    .pluck(:lead_id, :from_value, :created_at)
                                    .map { |id, ganho, em| [id, Time.zone.parse(ganho), em] }
                                    .select { |_id, ganho, _em| periodo.cover?(ganho) }
  end

  # Ganhos do período cujo cliente já foi convidado pro Painel do Cliente.
  def painel
    taxa(ganhos.where(PAINEL_SQL).count, ganhos.count)
  end

  # Cada marca "vou pensar" do período, retomada em até 48h (RETOMADA_SQL).
  def vou_pensar_48h
    marcas = atividades('vou_pensar').where(created_at: periodo, lead_id: dos_closers.select(:id))
    retomadas = marcas.where(RETOMADA_SQL)
    taxa(retomadas.count, marcas.where(created_at: ...48.hours.ago).or(retomadas).count)
  end

  def dia(momento)
    Time.zone.parse(momento.to_s).in_time_zone(TIME_ZONE).to_date
  end
end
