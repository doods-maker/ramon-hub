# Tela Hoje do SDR e do Closer ("equipe" = sem time: vê como SDR, sem filtrar dono).
class Ramon::Hoje::Comercial
  pattr_initialize [:account!, :user!, :papel!]

  def perform
    papel == 'closer' ? closer : sdr
  end

  private

  def zona = Time.find_zone!(Chegada::ZONA)

  def mes_atual = zona.now.all_month

  # Leads do funil em que a pessoa é o SDR/Closer. "equipe" (sem time) vê os leads
  # das caixas de que é membro — nunca lead de caixa alheia.
  def meus(coluna)
    leads = account.leads.funil.reorder(nil)
    return leads.where(coluna => user.id) unless equipe?

    leads.joins(:conversation).where(conversations: { inbox_id: user.inboxes.where(account_id: account.id).select(:id) })
  end

  def equipe? = papel == 'equipe'

  # "equipe" não recebe o texto da conversa, só que tem alguém esperando.
  def responder
    Ramon::Hoje::Prazo.sem_resposta(meus(:sdr_id)).limit(20).map do |lead|
      linha = Ramon::Hoje::Prazo.linha(lead)
      equipe? ? linha.merge(ultima_mensagem: '') : linha
    end
  end

  def sdr
    {
      responder: responder,
      follow_ups: follow_ups, reunioes: reunioes_marcadas, mes: mes(Ramon::Papeis::SDR)
    }
  end

  def closer
    { reunioes_hoje: reunioes_hoje, assinatura: assinatura, mes: mes(Ramon::Papeis::CLOSER).merge(fechamento: fechamento) }
  end

  def tarefas(kind, coluna)
    account.lead_tasks.open_tasks.where(kind: kind, lead_id: meus(coluna).select(:id))
           .preload(lead: [:thesis, :conversation]).order(:due_at)
  end

  def follow_ups
    tarefas('follow_up', :sdr_id).where(due_at: ..zona.now.end_of_day).limit(20).map do |task|
      { lead_id: task.lead_id, nome: task.lead.name, tese: task.lead.thesis&.name, titulo: task.title,
        vence_em: task.due_at.iso8601, conversa_id: task.lead.conversation&.display_id }
    end
  end

  def reunioes_marcadas
    tarefas('meeting', :sdr_id).where(due_at: zona.now.beginning_of_day..).preload(lead: :closer).limit(10).map do |task|
      { quando: task.due_at.iso8601, nome: task.lead.name, tese: task.lead.thesis&.name, closer: task.lead.closer&.name }
    end
  end

  def reunioes_hoje
    tarefas('meeting', :closer_id).where(due_at: zona.now.all_day).preload(lead: { thesis: :thesis_items }).map do |task|
      { quando: task.due_at.iso8601, lead_id: task.lead_id, nome: task.lead.name, tese: task.lead.thesis&.name, docs: task.lead.docs_counts }
    end
  end

  # Contrato enviado pelo ZapSign e lead ainda nem ganho nem perdido.
  def assinatura
    meus(:closer_id).where(won_at: nil, lost_at: nil).where("leads.custom_attributes #>> '{zapsign,doc_token}' IS NOT NULL")
                    .preload(:thesis, :conversation).map do |lead|
      { lead_id: lead.id, nome: lead.name, tese: lead.thesis&.name,
        enviado_em: lead.custom_attributes.dig('zapsign', 'criado_em'), conversa_id: lead.conversation&.display_id }
    end
  end

  def mes(papel_meta)
    linha = Ramon::ExtratoVariavel.new(account: account, mes: zona.today.beginning_of_month).pessoas
                                  .find { |pessoa| pessoa[:user][:id] == user.id && pessoa[:papel] == papel_meta }
    return { meta: nil, contagem: 0, total: 0, contratos: 0 } unless linha

    { meta: linha[:meta], contagem: linha[:contagem], total: linha[:total],
      contratos: linha[:unidades].count { |unidade| unidade[:evento] == 'contrato_limpo' } }
  end

  # % das reuniões registradas no mês que viraram ganho no mês (nunca passa de 100); nil sem reunião.
  def fechamento
    reunioes = meus(:closer_id).where(reuniao_registrada_em: mes_atual)
    total = reunioes.count
    return nil if total.zero?

    reunioes.where(won_at: mes_atual).count * 100 / total
  end
end
