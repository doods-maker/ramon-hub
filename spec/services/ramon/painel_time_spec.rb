require 'rails_helper'

RSpec.describe Ramon::PainelTime do
  let(:account) { create(:account) }
  let(:sdr) { create(:user, account: account, role: :agent, name: 'Sara SDR') }
  let(:closer) { create(:user, account: account, role: :agent, name: 'Caio Closer') }
  let(:novo) { account.lead_stages.find_by(name: 'Novo') }
  let(:qualif) { account.lead_stages.find_by(name: 'Qualificação') }
  let(:fechado) { account.lead_stages.find_by(is_won: true) }
  let(:perdido) { account.lead_stages.find_by(is_lost: true) }
  let(:agora) { Time.zone.parse('2026-11-18 17:00:00 UTC') } # quarta, 14h em SP

  around { |example| travel_to(agora) { example.run } }

  before do
    create(:team_member, team: create(:team, account: account, name: 'sdr'), user: sdr)
    create(:team_member, team: create(:team, account: account, name: 'closer'), user: closer)
  end

  def painel(papel)
    described_class.new(account: account, papel: papel, periodo: 'mes').perform
  end

  def kpis(papel)
    painel(papel)[:time][:kpis]
  end

  def lead(**attrs)
    create(:lead, account: account, lead_stage: novo, sdr: sdr, closer: closer, **attrs)
  end

  # Ganho com carimbos no passado, sem os callbacks de etapa recalcularem.
  def ganho(won_at, **cols)
    lead.tap { |alvo| alvo.update_columns(lead_stage_id: fechado.id, won_at: won_at, **cols) } # rubocop:disable Rails/SkipsModelValidations
  end

  def marca(alvo, kind, quando = agora)
    alvo.lead_activities.create!(account: account, kind: kind, created_at: quando)
  end

  describe 'SDR' do
    it 'show, não qualificada e registro completo no mesmo dia', :aggregate_failures do
      qualificada = lead(reuniao_resultado: 'qualificada', reuniao_registrada_em: agora)
      nao = lead(reuniao_resultado: 'nao_qualificada', reuniao_registrada_em: agora)
      2.times { marca(qualificada, 'reuniao_registrada') } # correção não conta 2x
      marca(nao, 'reuniao_registrada')
      marca(lead, 'meeting_no_show')
      marca(qualificada, 'registro_completo')

      expect(kpis('sdr')[:show]).to eq(valor: 66.7, num: 2, den: 3)
      expect(kpis('sdr')[:nao_qualificada]).to eq(valor: 50.0, num: 1, den: 2)
      expect(kpis('sdr')[:registro_completo]).to eq(valor: 33.3, num: 1, den: 3)
    end

    it '1ª resposta: mediana em minutos comerciais; sem resposta há +1h comercial agora', :aggregate_failures do
      inbox = create(:inbox, account: account, auto_create_lead: true)
      rapida, almoco, parada, recente = Array.new(4) { create(:conversation, account: account, inbox: inbox) }
      [rapida, almoco, parada, recente].each { |conversa| lead(conversation: conversa) }
      segunda = Time.zone.parse('2026-11-16 12:00:00 UTC') # 09:00 em SP
      create(:reporting_event, account: account, inbox: inbox, conversation: rapida,
                               event_start_time: segunda, event_end_time: segunda + 3.minutes)
      create(:reporting_event, account: account, inbox: inbox, conversation: almoco, # 11h55 → 13h35 = 10 min
                               event_start_time: segunda + 175.minutes, event_end_time: segunda + 275.minutes)
      [rapida, almoco].each { |conversa| conversa.update_columns(first_reply_created_at: segunda) } # rubocop:disable Rails/SkipsModelValidations
      parada.update_columns(created_at: agora - 4.hours) # rubocop:disable Rails/SkipsModelValidations
      recente.update_columns(created_at: agora - 1.hour) # rubocop:disable Rails/SkipsModelValidations

      expect(kpis('sdr')[:primeira_resposta]).to eq(valor: 6.5, num: 2, den: nil)
      expect(kpis('sdr')[:sem_resposta]).to eq(valor: 1, num: 1, den: 2)
    end

    it 'qualificado → agendada pela posição da etapa, sem os perdidos sem viabilidade' do
      marca(lead(lead_stage: qualif), 'meeting_scheduled')
      lead(lead_stage: qualif)
      lead # Novo: não chegou à Qualificação
      lead.tap { |passou| passou.update!(lead_stage: qualif) }.update!(lead_stage: perdido, lost_reason: 'Honorário')
      lead(lead_stage: qualif).update!(lead_stage: perdido, lost_reason: 'Sem viabilidade')

      expect(kpis('sdr')[:qualificado_agendada]).to eq(valor: 33.3, num: 1, den: 3)
    end

    it 'meta do mês × realizado do extrato e série de leads por dia', :aggregate_failures do
      MetaComercial.create!(account: account, user: sdr, papel: 'sdr', mes: Date.new(2026, 11, 1), meta: 25)
      lead(reuniao_resultado: 'qualificada', reuniao_registrada_em: agora)

      resposta = painel('sdr')
      expect(resposta[:time][:meta_mes]).to include(mes: '2026-11', meta: 25, realizado: 1, dias_uteis_restantes: 9)
      expect(resposta[:pessoas].map { |pessoa| pessoa[:user][:id] }).to eq([sdr.id])
      expect(resposta[:time][:volume][:total]).to eq(1)
      expect(resposta[:time][:volume][:serie].first).to eq(inicio: '2026-11-01', n: 0)
      expect(resposta[:metas][:primeira_resposta]).to eq(alvo: 5, sentido: 'max', unidade: 'min')
    end

    it 'agente (user) recebe só a própria linha, sem o agregado do time', :aggregate_failures do
      resposta = described_class.new(account: account, papel: 'closer', periodo: 'hoje', user: closer).perform

      expect(resposta[:time]).to be_nil
      expect(resposta[:pessoas].map { |pessoa| pessoa[:user][:id] }).to eq([closer.id])
    end
  end

  describe 'Closer' do
    let(:dez_dias) { agora - 10.days }

    it 'conversão, assinado na reunião e painel do cliente', :aggregate_failures do
      na_reuniao = ganho(dez_dias, reuniao_resultado: 'qualificada', reuniao_registrada_em: dez_dias,
                                   custom_attributes: { 'advbox' => { 'customers_id' => 777 } })
      create(:lead_task, account: account, lead: na_reuniao, kind: 'meeting', due_at: dez_dias - 1.hour, completed_at: dez_dias)
      ganho(dez_dias + 2.days, reuniao_resultado: 'qualificada', reuniao_registrada_em: dez_dias)
      lead(reuniao_resultado: 'qualificada', reuniao_registrada_em: dez_dias)
      create(:portal_cliente, account: account, advbox_customer_id: 777, convidado_em: dez_dias)

      expect(kpis('closer')[:conversao]).to eq(valor: 66.7, num: 2, den: 3)
      expect(kpis('closer')[:assinado_na_reuniao]).to eq(valor: 50.0, num: 1, den: 2)
      expect(kpis('closer')[:painel]).to eq(valor: 50.0, num: 1, den: 2)
    end

    it 'docs em 7 dias e dossiê em 24h: prazo correndo só conta se já cumpriu', :aggregate_failures do
      cumpriu = ganho(dez_dias, docs_completos_em: dez_dias + 3.days)
      marca(cumpriu, 'dossie_entregue', dez_dias + 2.hours)
      ganho(dez_dias)
      ganho(agora - 1.hour) # dentro do prazo, ainda sem nada: fora do denominador

      expect(kpis('closer')[:docs_7d]).to eq(valor: 50.0, num: 1, den: 2)
      expect(kpis('closer')[:dossie_24h]).to eq(valor: 50.0, num: 1, den: 2)
    end

    it 'cancelamento em 7 dias pela atividade contrato_cancelado (won_at antigo)', :aggregate_failures do
      ganho(dez_dias)
      cancelado = lead
      cancelado.update!(lead_stage: fechado)
      cancelado.update!(lead_stage: novo) # desistiu no mesmo dia

      expect(kpis('closer')[:cancelamento_7d]).to eq(valor: 50.0, num: 1, den: 2)
    end

    it '"vou pensar" retomado em 48h por mensagem da equipe ou follow-up', :aggregate_failures do
      inbox = create(:inbox, account: account)
      retomado = lead(conversation: create(:conversation, account: account, inbox: inbox))
      marca(retomado, 'vou_pensar', agora - 3.days)
      create(:message, account: account, inbox: inbox, conversation: retomado.conversation, message_type: :outgoing,
                       sender: closer, created_at: agora - 2.days)
      por_tarefa = lead
      marca(por_tarefa, 'vou_pensar', agora - 3.days)
      create(:lead_task, account: account, lead: por_tarefa, kind: 'follow_up', due_at: agora, created_at: agora - 2.days)
      marca(lead, 'vou_pensar', agora - 3.days)
      marca(lead, 'vou_pensar', agora - 1.hour) # ainda no prazo, sem retomada: fora

      expect(kpis('closer')[:vou_pensar_48h]).to eq(valor: 66.7, num: 2, den: 3)
    end
  end
end
