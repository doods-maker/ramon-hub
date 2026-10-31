require 'rails_helper'

RSpec.describe Ramon::DailyDigestService do
  # A conta seeda o funil no after_create; 12h em São Paulo = 15h UTC.
  let(:account) { create(:account) }
  let(:stage_novo) { account.lead_stages.find_by(name: 'Novo') }
  let(:service) { described_class.new(account: account) }

  def noon_brt(day)
    Time.utc(2026, 7, day, 15, 0, 0)
  end

  describe '#push_body' do
    it 'monta a linha completa: vencidas · SLA · reunião · valor em jogo' do
      travel_to noon_brt(23) do
        lead = create(:lead, account: account, lead_stage: stage_novo, benefit_monthly_value: 391_000)
        create(:lead_task, account: account, lead: lead, due_at: 2.days.ago)
        inbox = create(:inbox, account: account, auto_create_lead: true)
        create(:conversation, account: account, inbox: inbox).update_columns(created_at: 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations
        antonio = create(:lead, account: account, lead_stage: stage_novo, name: 'Antônio')
        create(:lead_task, account: account, lead: antonio, kind: 'meeting', due_at: Time.utc(2026, 7, 23, 18, 0, 0))

        expect(service.push_body).to eq('1 tarefa vencida · 1 fora do SLA · reunião 15h · R$ 391 mil em jogo')
      end
    end

    it 'omite as partes zeradas e mostra minutos da reunião quando não é hora cheia' do
      travel_to noon_brt(23) do
        lead = create(:lead, account: account, lead_stage: stage_novo, name: 'Maria das Dores')
        create(:lead_task, account: account, lead: lead, kind: 'meeting', due_at: Time.utc(2026, 7, 23, 18, 30, 0))

        expect(service.push_body).to eq('reunião 15h30')
      end
    end

    it 'vem nil com tudo zerado (o job não manda push)' do
      expect(service.push_body).to be_nil
    end

    it 'ignora caso de cálculo (fora do funil comercial)' do
      lead = create(:lead, account: account, lead_stage: stage_novo, source: Lead::FONTE_CALCULO, benefit_monthly_value: 5000)
      create(:lead_task, account: account, lead: lead, due_at: 2.days.ago)

      expect(service.push_body).to be_nil
    end

    it 'usa o SLA da própria inbox quando definido (COALESCE por conversa)' do
      travel_to noon_brt(23) do
        inbox = create(:inbox, account: account, auto_create_lead: true, first_response_sla_minutes: 60)
        create(:conversation, account: account, inbox: inbox).update_columns(created_at: 30.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

        expect(service.push_body).to be_nil
      end
    end

    it 'conta lead parado no valor em jogo mesmo sem tarefa vencida' do
      lead = create(:lead, account: account, lead_stage: stage_novo, benefit_monthly_value: 800)
      lead.update_column(:stage_entered_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations

      expect(service.push_body).to eq('R$ 800 em jogo')
    end
  end

  describe '#yesterday_stats' do
    it 'traz novos, ganhos com valor, perdidos com motivo top e 1ª resposta média de ontem' do
      travel_to noon_brt(23) do
        yesterday = noon_brt(22)
        create_list(:lead, 2, account: account, lead_stage: stage_novo).each do |lead|
          lead.update_column(:created_at, yesterday) # rubocop:disable Rails/SkipsModelValidations
        end
        won_lead = create(:lead, account: account, lead_stage: stage_novo, value: 71_000)
        won_lead.update_column(:won_at, yesterday) # rubocop:disable Rails/SkipsModelValidations
        create(:lead, account: account, lead_stage: stage_novo)
          .update_columns(lost_at: yesterday, lost_reason: 'sem carência') # rubocop:disable Rails/SkipsModelValidations
        inbox = create(:inbox, account: account, auto_create_lead: true)
        create(:conversation, account: account, inbox: inbox)
          .update_columns(created_at: yesterday, first_reply_created_at: yesterday + 10.minutes) # rubocop:disable Rails/SkipsModelValidations

        stats = service.yesterday_stats
        expect(stats[:date_label]).to eq('quarta, 22 de julho')
        expect(stats[:new_leads]).to eq(2)
        expect(stats[:won]).to eq(count: 1, value_label: 'R$ 71 mil')
        expect(stats[:lost]).to eq(count: 1, reason: 'sem carência')
        expect(stats[:first_response_label]).to eq('10min')
      end
    end

    it 'dia vazio: contadores zerados e labels nulos' do
      stats = service.yesterday_stats
      expect(stats[:new_leads]).to eq(0)
      expect(stats[:won]).to eq(count: 0, value_label: nil)
      expect(stats[:lost]).to eq(count: 0, reason: nil)
      expect(stats[:first_response_label]).to be_nil
    end

    describe 'agenda_sem_google' do
      let(:sdr_team) { create(:team, account: account, name: 'sdr') }
      let(:closer_team) { create(:team, account: account, name: 'closer') }
      let(:ana) { create(:user, account: account, name: 'Ana') }
      let(:caio) { create(:user, account: account, name: 'Caio') }

      before do
        create(:team_member, team: sdr_team, user: ana)
        create(:team_member, team: closer_team, user: caio)
      end

      it 'lista quem não tem Google conectado e some quando todos conectaram' do
        GoogleAgendaConta.create!(user: ana, account: account, refresh_token: 'rt', access_token: 'at')
        expect(service.yesterday_stats[:agenda_sem_google]).to eq(['Caio'])

        GoogleAgendaConta.create!(user: caio, account: account, refresh_token: 'rt', access_token: 'at')
        expect(service.yesterday_stats[:agenda_sem_google]).to eq([])
      end

      it 'conta desconectada conta como sem Google' do
        GoogleAgendaConta.create!(user: ana, account: account, refresh_token: 'rt', access_token: 'at', status: 'desconectada')
        GoogleAgendaConta.create!(user: caio, account: account, refresh_token: 'rt', access_token: 'at')
        expect(service.yesterday_stats[:agenda_sem_google]).to eq(['Ana'])
      end
    end

    describe 'funil_auto (o que a IA mexeu ontem)' do
      let(:lead) { create(:lead, account: account, lead_stage: stage_novo, name: 'Maria') }

      def acao(created_at:, **attrs)
        FunilAcao.create!({ account: account, lead: lead, peca: 'tempo_perdido', acao: 'mover_etapa', motivo: 'sem resposta',
                            alvo: 'Perdido', ensaio: false, created_at: created_at }.merge(attrs))
      end

      it 'traz a ação de ontem e ignora a de hoje' do
        travel_to noon_brt(23) do
          acao(created_at: noon_brt(22))
          acao(created_at: noon_brt(23), motivo: 'de hoje')

          expect(service.yesterday_stats[:funil_auto]).to eq(
            [{ lead_id: lead.id, lead_name: 'Maria', conversation_id: nil, texto: 'moveu para Perdido: sem resposta', ensaio: false }]
          )
        end
      end

      it 'marca a ação desfeita e o ensaio' do
        travel_to noon_brt(23) do
          acao(created_at: noon_brt(22), desfeita_em: noon_brt(22) + 1.hour)
          acao(created_at: noon_brt(22) + 1.minute, ensaio: true)

          textos = service.yesterday_stats[:funil_auto].pluck(:texto)
          expect(textos).to eq(['moveu para Perdido: sem resposta (desfeita)', 'faria: moveu para Perdido: sem resposta'])
        end
      end

      it 'a mesma ação repetida no mesmo lead aparece uma vez só' do
        travel_to noon_brt(23) do
          2.times { |i| acao(created_at: noon_brt(22) + i.hours, ensaio: true) }

          stats = service.yesterday_stats
          expect(stats[:funil_auto].size).to eq(1)
          expect(stats[:funil_auto_restantes]).to eq(0)
        end
      end

      it 'além do limite, mostra só os primeiros e conta o resto' do
        travel_to noon_brt(23) do
          (described_class::FUNIL_AUTO_LIMITE + 2).times do |i|
            outro = create(:lead, account: account, lead_stage: stage_novo)
            acao(created_at: noon_brt(22) + i.minutes, lead: outro)
          end

          stats = service.yesterday_stats
          expect(stats[:funil_auto].size).to eq(described_class::FUNIL_AUTO_LIMITE)
          expect(stats[:funil_auto_restantes]).to eq(2)
        end
      end
    end
  end
end
