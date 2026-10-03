require 'rails_helper'

RSpec.describe Ramon::Hoje::Comercial do
  let(:account) { create(:account) }
  let(:sdr) { create(:user, account: account) }
  let(:outro) { create(:user, account: account) }
  let(:closer) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account, auto_create_lead: true) }

  def lead_sem_resposta(dono)
    create(:lead, account: account, sdr: dono, conversation: create(:conversation, account: account, inbox: inbox))
  end

  def blocos(user, papel)
    described_class.new(account: account, user: user, papel: papel).perform
  end

  it 'SDR só vê os próprios leads em "responder"' do
    meu = lead_sem_resposta(sdr)
    lead_sem_resposta(outro)
    expect(blocos(sdr, 'sdr')[:responder].pluck(:lead_id)).to eq([meu.id])
  end

  it 'equipe vê os leads das caixas de que é membro, sem o texto da conversa' do
    create(:inbox_member, user: sdr, inbox: inbox)
    da_caixa = lead_sem_resposta(outro)
    create(:message, account: account, inbox: inbox, conversation: da_caixa.conversation, message_type: :incoming, content: 'segredo')
    alheia = create(:inbox, account: account, auto_create_lead: true)
    create(:lead, account: account, sdr: outro, conversation: create(:conversation, account: account, inbox: alheia))
    responder = blocos(sdr, 'equipe')[:responder]
    expect(responder.pluck(:lead_id)).to eq([da_caixa.id])
    expect(responder.first[:ultima_mensagem]).to eq('')
  end

  it 'SDR sem nada: listas vazias e mês zerado' do
    expect(blocos(sdr, 'sdr')).to include(responder: [], follow_ups: [], reunioes: [],
                                          mes: { meta: nil, contagem: 0, total: 0, contratos: 0 })
  end

  it 'follow-up vencido do meu lead aparece; o de outro SDR e o concluído não' do
    lead = create(:lead, account: account, sdr: sdr)
    create(:lead_task, account: account, lead: lead, kind: 'follow_up', title: 'Retomada nº 1', due_at: 1.hour.ago)
    create(:lead_task, account: account, lead: lead, kind: 'follow_up', title: 'Feita', due_at: 1.hour.ago, completed_at: Time.current)
    create(:lead_task, account: account, lead: create(:lead, account: account, sdr: outro), kind: 'follow_up', due_at: 1.hour.ago)
    follow_ups = blocos(sdr, 'sdr')[:follow_ups]
    expect(follow_ups.size).to eq(1)
    expect(follow_ups.first).to include(titulo: 'Retomada nº 1', lead_id: lead.id)
  end

  it 'reunião que o SDR marcou aparece com o closer' do
    lead = create(:lead, account: account, sdr: sdr, closer: closer)
    create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reunião', due_at: 2.days.from_now)
    expect(blocos(sdr, 'sdr')[:reunioes].first).to include(nome: lead.name, closer: closer.name)
  end

  it 'closer: reunião de hoje com a contagem de documentos' do
    lead = create(:lead, account: account, closer: closer)
    create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reunião', due_at: Time.current)
    expect(blocos(closer, 'closer')[:reunioes_hoje].first).to include(lead_id: lead.id, docs: { received: 0, total: 0 })
  end

  it 'closer: fechamento = ganhos do mês entre as reuniões do mês (nunca passa de 100)' do
    ganho = account.lead_stages.find_by(is_won: true)
    create(:lead, account: account, closer: closer, lead_stage: ganho, reuniao_registrada_em: Time.current)
    create(:lead, account: account, closer: closer, reuniao_registrada_em: Time.current)
    create(:lead, account: account, closer: closer, lead_stage: ganho) # ganho sem reunião no mês não conta
    expect(blocos(closer, 'closer')[:mes][:fechamento]).to eq(50)
  end

  it 'closer: aguardando assinatura = zapsign enviado e ainda não ganho' do
    lead = create(:lead, account: account, closer: closer,
                         custom_attributes: { 'zapsign' => { 'doc_token' => 'x', 'criado_em' => 1.day.ago.iso8601 } })
    create(:lead, account: account, closer: closer)
    resultado = blocos(closer, 'closer')
    expect(resultado[:assinatura].pluck(:lead_id)).to eq([lead.id])
    expect(resultado[:mes]).to include(contagem: 0, fechamento: nil)
  end
end
